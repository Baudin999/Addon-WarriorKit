local ADDON, ns = ...

local Window = {}
ns.QuestWindow = Window

local UI = ns.UI
local C, M = UI.Color, UI.Metric
local Log, Where = ns.QuestLog, ns.QuestWhere

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
-- changed, which is four events, and every one of them ends in Refresh. The
-- distance in the right column is the one number that goes stale between
-- events, and it is redrawn when you click a quest rather than five times a
-- second, because a quest log open on the screen is not a compass.
--------------------------------------------------------------------------

local WIDTH, HEIGHT = 780, 520

-- The two fixed columns. The middle takes whatever is left, which is the way
-- round it has to be: a zone name and an item name have a length the font
-- decides, and prose does not.
local LIST, PAY = 220, 200

-- One reward's picture, and the mark down the left of an objective line. Both
-- are the width their column reserves before the words start, so the ticks line
-- up down one edge and the icons down the other.
local SLOT, MARK = 22, 10

local window, list
local page, pay
local showing = nil

-- Whether the abandon button has been pressed once. Cleared by anything that
-- changes which quest is showing, because the second press has to be about the
-- quest the first press was about. The mail window arms its send the same way
-- and for the same reason.
local armed = false

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

	row.mark = UI.Label(row, M.small, C.quiet, "LEFT", UI.FLAT)
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
				rows[#rows + 1] = {
					id = quest.key,
					label = Label(quest),
					color = Tint(quest),
				}
			end
		end
	end
	return rows
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
	return table.concat(parts, "  ·  ")
end

local function DrawPage(detail)
	Start(page)

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

	if #detail.objectives > 0 then
		Caption(page, "objectives")
		for _, line in ipairs(detail.objectives) do
			Line(page, {
				text = line.text,
				color = line.done and C.dim or C.text,
				mark = line.done and "+" or "-",
				markColor = line.done and C.tick or C.quiet,
			})
		end
	elseif detail.summary ~= "" then
		Caption(page, "objectives")
		Line(page, { text = detail.summary, gap = M.gutter })
	end

	if detail.description ~= "" then
		page.stack:Space(M.gutter)
		Caption(page, "the quest")
		Line(page, { text = detail.description, color = C.dim })
	end

	Finish(page)
end

--------------------------------------------------------------------------
-- The right column
--------------------------------------------------------------------------

-- The coin and the counts, in the order they matter to somebody handing a quest
-- in. Money first, because it is the one every quest has.
local function Payment(rewards)
	if type(rewards.money) == "number" and rewards.money > 0 then
		Line(pay, { text = ns.Coin(rewards.money), size = M.small })
	end
	if type(rewards.required) == "number" and rewards.required > 0 then
		Line(pay, {
			text = ("costs %s"):format(ns.Coin(rewards.required)),
			size = M.small,
			color = C.loss,
		})
	end
	if type(rewards.xp) == "number" and rewards.xp > 0 then
		Line(pay, { text = ("%d experience"):format(rewards.xp), size = M.small, color = C.dim })
	end
	if type(rewards.honor) == "number" and rewards.honor > 0 then
		Line(pay, { text = ("%d honor"):format(rewards.honor), size = M.small, color = C.dim })
	end
	if type(rewards.title) == "string" and rewards.title ~= "" then
		Line(pay, { text = rewards.title, size = M.small, color = C.heading })
	end
	if rewards.spell then
		Line(pay, {
			text = ("teaches %s"):format(rewards.spell.name),
			size = M.small,
			color = C.hint,
		})
	end
end

-- One reward: the item's picture, its name in its quality colour, the stack
-- size when there is more than one, and the item's own text in the hover.
--
-- That hover is why Quests/Client.lua reads the link at all. It is the only way
-- to answer "is this better than what I am wearing" without this addon carrying
-- an item database, and UI/Scan.lua is what reads the real text out of the
-- client to fill it.
local function Payout(caption, items)
	if #items == 0 then
		return false
	end
	Caption(pay, caption)
	for _, item in ipairs(items) do
		Line(pay, {
			text = item.count and ("%s x%d"):format(item.name, item.count) or item.name,
			size = M.small,
			color = UI.Quality[item.quality or 1] or C.text,
			icon = item.texture,
			link = item.link,
			name = item.name,
		})
	end
	return true
end

-- The two lines Questie pays for. Absent rather than empty when it is not
-- installed, because a caption over nothing is a window telling you it is
-- broken when it is doing exactly what it said it would.
local function Bearing(quest)
	local finisher = Where.Finisher(quest.id)
	local nearest, yards = Where.Nearest(quest.id)
	if not finisher and not nearest then
		return false
	end

	pay.stack:Space(M.gutter)
	Caption(pay, "where")
	if nearest then
		Line(pay, {
			text = yards and ("%s, %d yards"):format(nearest, yards) or nearest,
			size = M.small,
		})
	end
	if finisher then
		Line(pay, {
			text = ("hand in to %s"):format(finisher),
			size = M.small,
			color = C.dim,
		})
	end
	return true
end

local function DrawPay(detail)
	Start(pay)

	local rewards = detail.rewards
	local choices = rewards.choices or {}
	if Payout("choose one", choices) then
		pay.stack:Space(M.rowGap)
	end
	if Payout(#choices > 0 and "and also" or "you get", rewards.items or {}) then
		pay.stack:Space(M.rowGap)
	end

	Payment(rewards)
	Bearing(detail.quest)

	Finish(pay)
end

--------------------------------------------------------------------------
-- The whole window
--------------------------------------------------------------------------

-- A column with its own scroll view, its own stack and its own pool of lines,
-- which is what both the middle and the right are.
local function Column(parent)
	local column = { pool = {}, at = 0 }
	column.frame = CreateFrame("Frame", nil, parent)
	column.view = UI.ScrollView(column.frame)
	column.view.frame:SetPoint("TOPLEFT")
	column.stack = UI.Stack(column.view.canvas)
	return column
end

local function Select(key)
	if painting then
		return
	end
	showing = key
	armed = false
	Window.Paint()
end

-- The two rules between the columns, and the three buttons in the footer.
local function Chrome()
	window.leftRule = UI.Rule(window.content, C.hairline, true)
	window.leftRule:SetPoint("TOPLEFT", list.frame, "TOPRIGHT", M.gutter, 0)
	window.leftRule:SetPoint("BOTTOMLEFT", list.frame, "BOTTOMRIGHT", M.gutter, 0)

	window.rightRule = UI.Rule(window.content, C.hairline, true)
	window.rightRule:SetPoint("TOPRIGHT", pay.frame, "TOPLEFT", -M.gutter, 0)
	window.rightRule:SetPoint("BOTTOMRIGHT", pay.frame, "BOTTOMLEFT", -M.gutter, 0)

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

	window.track = UI.Button(window.footer, {
		label = "track",
		width = 60,
		onClick = function() Window.Track() end,
	})
	window.track:SetPoint("RIGHT", window.share, "LEFT", -M.rowGap, 0)
end

-- Every column sized off the window, in one place rather than nine, because a
-- resolution change has to be able to call it again.
function Window.Fit()
	if not window then
		return false
	end
	local body = window:Body()
	local middle = WIDTH - LIST - PAY - M.pad * 2

	list:Resize(LIST, body)
	page.frame:SetSize(middle, body)
	page.view:Resize(middle, body)
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
	})

	list = UI.List(window.content, {
		name = "WarriorKitQuestList",
		onSelect = Select,
	})
	list.frame:SetPoint("TOPLEFT")

	page = Column(window.content)
	page.frame:SetPoint("TOPLEFT", list.frame, "TOPRIGHT", M.pad, 0)

	pay = Column(window.content)
	pay.frame:SetPoint("TOPRIGHT")

	Chrome()
	Window.Fit()
	return window
end

--------------------------------------------------------------------------

function Window.PaintFooter(detail)
	local total, done = Log.Tally()
	window.tally:SetText(("%d quests, %d ready to hand in"):format(total, done))

	local quest = detail and detail.quest
	local shareable = (detail and detail.shareable) and true or false

	window.track.text:SetText(quest and quest.watched and "untrack" or "track")
	window.track:EnableMouse(quest ~= nil)
	window.track:SetAlpha(quest and 1 or 0.4)

	window.share:EnableMouse(shareable)
	window.share:SetAlpha(shareable and 1 or 0.4)

	window.abandon.text:SetText(armed and "abandon it" or "abandon")
	UI.Tint(window.abandon.bg, armed and C.danger or C.control)
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
		armed = false
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

	Window.PaintFooter(detail)
	painting = false
	return true
end

--------------------------------------------------------------------------
-- The three buttons
--------------------------------------------------------------------------

function Window.Track()
	local quest = Log.Quest(showing)
	if not quest then
		return false
	end
	Log.Watch(showing, not quest.watched)
	Window.Paint()
	return true
end

function Window.Share()
	if not showing then
		return false
	end
	local shared = Log.Share(showing)
	if not shared then
		ns.Print("this client would not share that quest.")
	end
	return shared
end

-- Two presses, and the first one says out loud what the second would do.
--
-- The name comes from the client's own armed state rather than from the row
-- this window thinks is selected, which is the whole point: if the two ever
-- disagree, the message is what tells you before the quest is gone rather than
-- after.
function Window.Abandon()
	if not showing then
		return false
	end
	if not armed then
		local name = Log.Abandoning(showing)
		if not name then
			ns.Print("this client would not offer that quest up.")
			return false
		end
		armed = true
		ns.Print(("press again to abandon %s."):format(name))
		Window.PaintFooter(Log.Detail(showing))
		return false
	end

	armed = false
	local gone = Log.Abandon(showing)
	showing = nil
	Window.Paint()
	return gone
end

--------------------------------------------------------------------------

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
		ns.QuestBlizzard.Apply()
		return
	end
	Window.Refresh()
end)

-- The grid moved: the screen changed size, combat let go of a frame, or the
-- player dragged the UI size slider. The window is taken back onto the grid at
-- the new zoom and then laid out again, in that order, because every number Fit
-- uses is in the window's own units and those units are what just changed.
UI.OnRescale(function()
	if not window then
		return
	end
	UI.Rezoom(window.frame, UI.WindowZoom())
	window.zoom = UI.WindowZoom()
	Window.Fit()
	Window.Refresh()
end)
