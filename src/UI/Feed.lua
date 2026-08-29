local ADDON, ns = ...

local UI = ns.UI
local C, M = UI.Color, UI.Metric

--------------------------------------------------------------------------
-- The feed
--
-- A column of things that happened, newest at the top, older below it, and the
-- older ones still there when you scroll down to look.
--
-- **Why this is not UI/Log.lua.** That file is a column of strings and the
-- client's own ScrollingMessageFrame draws it, which is exactly right for
-- conversation and cannot do this: a message frame holds text and nothing else,
-- so an icon per line is not something it can be asked for. A row here is an
-- icon, a name, a number and a coloured mark down its left edge, which is four
-- regions the client has no line type for.
--
-- **Why this is not UI/Stack.lua and UI/Scroll.lua.** Those lay a column out by
-- asking every row how tall it is and placing them one under the next, which
-- means a row arriving reflows the whole column. UI/Log.lua's header already
-- argues that case and refuses it, and a feed is the same argument again with a
-- worse constant: four hundred entries measured every time a mob drops
-- something.
--
-- **So the rows do not move.** There is one frame per visible row, built once,
-- anchored once, and never anchored again. What arrives is written into a ring
-- of entries, and scrolling is an offset into that ring: the rows keep their
-- positions and repaint from a different place in the list. Ten rows repaint
-- whether the feed holds ten entries or four hundred, so a scroll costs the
-- same as a drop and both cost ten guarded writes.
--
-- That also means there is no clipping to arrange, no canvas to move and no
-- ScrollFrame to probe. The rows exactly fill the space, so there is nothing
-- to clip.
--
-- **Nothing here is on a ticker.** A feed changes when something happens to
-- you, which is an event, and it changes when you scroll it, which is a
-- gesture. A relative timestamp on a row would be the one thing that has to be
-- redrawn while nothing is happening, which is why a row carries no clock and
-- the tooltip is where the time is: opening a tooltip is a moment, and a moment
-- can afford to build a string.
--
-- **A row has three text columns and the middle one is optional.** A name and a
-- number were not enough for the combat log: "Overpower 321" and "Plains
-- Creeper 26" are the same shape and only one of them is a spell, so there was
-- no reading a row and knowing who had done what to whom. The middle column is
-- dim, right aligned against the number, and asked for by the caller in units,
-- so the loot feed keeps two columns and the combat feed gets three without
-- either being a special case in here. All three widths are decided per resize
-- rather than per row, which is why a run of numbers reads as a column.
--
-- **A marker is a break in the timeline, not an entry in it.** Feed:Mark pushes
-- one and it draws as a band across the whole row with a word on it: no icon,
-- no middle column, nothing a thing that happened to you can look like. Here
-- rather than faked in Feeds/Combat.lua because "one set of events ends and
-- another begins" is a thing any feed wants, and a marker built out of an
-- ordinary row is one an ordinary row can be mistaken for.
--------------------------------------------------------------------------

-- Every number is a unit, which is one physical pixel inside a frame
-- ns.UI.Adopt has taken onto the grid, and a whole block of them above zoom 1.
--
-- The icon is 27 for the reason Meter/Window.lua's is: the client stores a
-- spell or item icon at 64 texels, UI/Draw.lua's crop leaves 54 of them, and a
-- draw is one texel per pixel only at 54 and 27. Everything else on a row
-- follows from it.
-- What an icon is drawn at before anybody moves the slider, and the two units
-- of row it leaves round itself. The row is the icon plus the pad rather than a
-- number of its own, because the two were 29 and 27 and a slider that moved one
-- without the other would either crop the art or leave a gap that grew.
local ICON = 27
local ROW_PAD = 2
local ROW_GAP = 1
-- The strip over the rows. It was 16, which was a heading and nothing else in
-- it; a chip is a square you have to be able to hit with a mouse at a UI scale
-- of one half, and 16 left it no air at all.
local HEADER = 20
local RULE = 1
local INSET = 3     -- the stripe to the icon
local STRIPE = 2    -- the coloured mark down the left of a row
local GUTTER = 5    -- the icon to the name
local PAD = 4       -- one text column to the next

-- How small and how large a row's icon can be asked to go.
--
-- The floor is the text, not the art. Every string on a row is outlined and
-- ns.UI.OutlineFloor puts an outlined glyph at 14 or above, so a row shorter
-- than 16 is a row whose name does not fit in it however small the picture
-- gets. The ceiling is one step past ns.UI.IconTexels halved, which is 27 and
-- the one size in this range that draws a stored texel per screen pixel; past
-- 40 a feed row is taller than the tooltip describing it.
--
-- Published rather than local because Feeds/Feature.lua puts the stepper on a
-- panel page and a second copy of the range is a second thing to keep in step.
UI.FEED_ICON, UI.FEED_ICON_LOW, UI.FEED_ICON_HIGH = ICON, 16, 40

-- One filter chip: a small square of the addon's own furniture with a mark on
-- it, in the strip over the rows. Sixteen units inside a twenty unit header,
-- which is the same two units of air the heading text gets.
local CHIP = 16
local CHIP_GAP = 3
local CHIP_MARK = 14
-- The air that separates one run of chips from the next. Three units says
-- nothing; most of a chip's width says these two are different questions.
local CHIP_BREAK = 10
-- What the mark on a chip that is switched off is painted at. Not hidden and
-- not greyed: the colour and the shape are what say which chip it is, so an off
-- chip keeps both and loses its light. Low enough to read as off across the
-- room and high enough to still find with a cursor.
local CHIP_OFF = 0.3

-- The number column, fixed rather than grown to fit. A string that sizes itself
-- puts every number at a different distance from the edge, which is a ragged
-- column of damage. Six glyphs of Arial Narrow at the row size, which is a five
-- figure hit with a crit mark on it.
local AMOUNT = 42

-- Outlined, so both sizes sit at or above ns.UI.OutlineFloor. A feed is drawn
-- over the world with whatever background the player asked for, and at zero
-- background that is outlined text on grass. Flat text does not get softer
-- there, it goes.
-- Outlined, every string in this file, and both sizes at UI.OutlineFloor().
--
-- A feed looks like it is drawn on a surface, and it is not one this addon can
-- promise anything about: the background is a slider the player drags, it goes
-- to zero, and Feeds/Feature.lua tells them in writing that the text reads all
-- the way down to nothing. At zero a feed is rows of text over the world, so
-- the rim is the only thing holding them off it.
--
-- That is also why neither size is a setting and why both are 14 rather than
-- the panel's 12. An outlined glyph spends a pixel of every stroke on the rim,
-- so a string that must be outlined must also be tall enough to survive one,
-- and UI/Text.lua puts that floor at 14. Anything smaller here would be wrong
-- both ways at once: too small to carry a rim and unable to drop it.
local ROW_TEXT = 14
local HEADER_TEXT = 14

-- How far one notch of the wheel moves. Three is what UI/Log.lua uses, what
-- UI/Scroll.lua uses, and what every window in the game uses.
local WHEEL_ROWS = 3

-- The most rows a feed will ever be asked to draw, and how many entries it
-- keeps behind them. A frame cannot be destroyed on this client, so the rows
-- are built once at this count and the setting decides how many are shown.
local MAX_ROWS = 24
local HELD = 400

-- What the bottom row fades to when there is more underneath it.
--
-- The one piece of decoration in this file, and it is carrying information
-- rather than atmosphere: it is the difference between a feed that has stopped
-- and a feed that continues past the bottom edge. The scrollbar says the same
-- thing and says it in eight pixels off to the side, which is not where you are
-- looking. Written once per row per paint, behind a guard, and it costs nothing
-- because it is a function of the row's position rather than of the clock.
local FADE = 0.45

local Feed = {}
Feed.__index = Feed

-- How many screen pixels of art a row icon draws at a given size and zoom, and
-- whether that is one stored texel per pixel.
--
-- Read out of ns.UI.IconSizes rather than typed, so changing the crop in
-- UI/Draw.lua moves this answer instead of leaving a stale number in a panel
-- note. Meter/Window.lua answers the same question about its own rows and the
-- two are deliberately separate: they are allowed to pick different icon sizes,
-- and a shared function would be a shared decision.
--
-- The size is an argument now that it is a setting. It was this file's own
-- constant and the panel note that read it was therefore telling every player
-- the same thing whatever they had dragged the slider to, which is the exact
-- failure a note computed from a constant always has.
function UI.FeedIcons(size, zoom)
	local drawn = (size or ICON) * (zoom or 1)
	for _, exact in ipairs(UI.IconSizes()) do
		if exact == drawn then
			return drawn, true
		end
	end
	return drawn, false
end

--------------------------------------------------------------------------
-- One row
--------------------------------------------------------------------------

local function BuildRow(feed, index)
	local unit = feed.unit
	local row = CreateFrame("Frame", nil, feed.frame)
	-- Both numbers are written in Resize, because both follow the icon size and
	-- that is a slider. A row built at one height and never told about the next
	-- one is a column that keeps the size it had at login.
	row:SetSize(1, 1)
	row.index = index

	-- Behind everything, and only while the mouse is on it. A feed you can
	-- hover has to answer the hover with something other than a tooltip
	-- appearing off to one side, or there is no telling which row it is about.
	row.glow = ns.Fill(row, "BACKGROUND", C.hover[1], C.hover[2], C.hover[3], 0.5)
	row.glow:SetAllPoints()
	row.glow:Hide()

	-- The timeline itself. One segment per row, separated by the row gap, so a
	-- run of entries reads as a ribbon down the left edge broken into the
	-- things that made it. Its colour is the entry's, which for loot is the
	-- item's quality and for the combat log is what kind of event it was, and
	-- that is most of what you get from a feed at a glance without reading it.
	row.stripe = ns.Fill(row, "ARTWORK", C.edge[1], C.edge[2], C.edge[3], 1)
	row.stripe:SetPoint("TOPLEFT")
	row.stripe:SetPoint("BOTTOMLEFT")
	row.stripe:SetWidth(STRIPE * unit)

	row.icon = UI.Icon(row, "ARTWORK")
	row.icon:SetPoint("LEFT", row, "LEFT", (STRIPE + INSET) * unit, 0)

	-- A ring round the icon, for the one thing about an item that its quality
	-- colour cannot say. A quest item is white, the same white as a stack of
	-- linen, and the row that hands in your chain of five kills reads exactly
	-- like the row that hands you a bandage.
	--
	-- A frame rather than four textures anchored to the icon, because ns.Outline
	-- pins its edges to the corners of the frame it is given and the icon is a
	-- texture. Built once per row and shown on the rows that have earned it: the
	-- alternative is building it on the arrival that needs it, on the path a
	-- pull drives.
	row.mark = UI.Box(row, nil, C.edge)
	row.mark:SetPoint("TOPLEFT", row.icon, "TOPLEFT")
	row.mark:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT")
	row.mark:Hide()

	-- Every column is given its width in Resize, and never its right edge.
	-- Chaining each one's right edge to the next one's left, which is what this
	-- did with two columns, lets a long name push a number about and makes the
	-- columns disagree row to row. A clipped name is still the right item; a
	-- clipped number is a lie, which is Meter/Window.lua's rule and is why the
	-- number is the column that never gives way.
	--
	-- The name is anchored in Resize rather than here, because where it starts
	-- is behind the icon and the icon is a slider. The other two are pinned to
	-- the right edge and do not move when the picture does.
	row.name = UI.Label(row, ROW_TEXT, C.text, "LEFT", UI.OUTLINE)

	row.note = UI.Label(row, ROW_TEXT, C.dim, "RIGHT", UI.OUTLINE)
	row.note:SetPoint("RIGHT", row, "RIGHT", -(INSET + AMOUNT + PAD) * unit, 0)
	row.note:Hide()

	row.amount = UI.Label(row, ROW_TEXT, C.text, "RIGHT", UI.OUTLINE)
	row.amount:SetPoint("RIGHT", row, "RIGHT", -INSET * unit, 0)

	-- The word on a marker, which starts where the icon would and therefore
	-- cannot be the same font string as the name. Its own string rather than the
	-- name moved, because moving it means a SetPoint on the repaint path and a
	-- second font string per row is both cheaper and incapable of going stale.
	row.caption = UI.Label(row, ROW_TEXT, C.text, "LEFT", UI.OUTLINE)
	row.caption:SetPoint("LEFT", row, "LEFT", (STRIPE + INSET) * unit, 0)
	row.caption:Hide()

	row:SetScript("OnEnter", function(self)
		feed:Enter(self.index)
	end)
	row:SetScript("OnLeave", function()
		feed:Leave()
	end)
	UI.PassCamera(row)
	row:EnableMouse(false)

	row:Hide()
	return row
end

-- The three regions the strip over the rows is made of, and the line that
-- stands where the rows would be before anything has happened.
--
-- All four are built whether or not anything is going to ask for them, because
-- a frame cannot be destroyed on this client: a heading made the first time
-- somebody switched one on is a heading that can never be unmade, and the pool
-- would grow by one per click. Feed:Chrome shows and hides them.
local function BuildHeader(feed)
	if feed.title then
		feed.heading = UI.Label(feed.frame, HEADER_TEXT, C.dim, "LEFT", UI.OUTLINE)
		feed.heading:SetPoint("TOPLEFT", feed.frame, "TOPLEFT",
			INSET * feed.unit, -INSET * feed.unit)
		feed.heading:SetText(feed.title)
	end

	feed.tally = UI.Label(feed.frame, HEADER_TEXT, C.quiet, "RIGHT", UI.OUTLINE)
	feed.tally:SetPoint("TOPRIGHT", feed.frame, "TOPRIGHT",
		-INSET * feed.unit, -INSET * feed.unit)

	feed.rule = ns.Fill(feed.frame, "ARTWORK", C.hairline[1], C.hairline[2],
		C.hairline[3], 1)
	feed.rule:SetPoint("TOPLEFT", feed.frame, "TOPLEFT", 0, -HEADER * feed.unit)
	feed.rule:SetHeight(RULE * feed.unit)

	feed.blank = UI.Label(feed.frame, ROW_TEXT, C.quiet, "LEFT", UI.OUTLINE)
	feed.blank:SetText(feed.empty or "")
	return feed
end

--------------------------------------------------------------------------
-- Standing one up
--
-- opts.title     the word over the column, and nothing drawn above the rows
--                when there is none
-- opts.empty     what is written where the rows would be before anything has
--                happened
-- opts.held      how many entries this feed keeps
-- opts.note      how wide the dim middle column is, in units, and zero for a
--                feed that does not want one
-- opts.onTooltip function(entry), answering the table UI/Tooltip.lua renders for
--                the row under the cursor
-- opts.unit      one design pixel in the parent's units, which the caller
--                already read off the frame it adopted
-- opts.chips     the filter strip over the rows, or nothing for a feed with
--                none. See Feed:BuildChips
-- opts.filter    function(entry), whether an entry is drawn at all. Nothing at
--                all for a feed that draws everything it holds, which is not
--                the same as a filter that always answers true: the first costs
--                nothing and the second walks the ring
--------------------------------------------------------------------------

function UI.Feed(parent, opts)
	opts = opts or {}

	local feed = setmetatable({
		unit = opts.unit or UI.Unit(parent),
		title = opts.title,
		empty = opts.empty,
		note = opts.note or 0,
		onTooltip = opts.onTooltip,
		-- The predicate as the caller wrote it, and the one the paint actually
		-- uses. They differ while the chips are hidden, which is the only time
		-- a feed with a filter draws everything it holds.
		onFilter = opts.filter,
		filter = nil,
		cap = opts.held or HELD,
		-- The icon size, and the row height that follows it. Both are settings
		-- and both are written by Resize; these are what a feed draws at before
		-- anybody has said otherwise.
		icon = ICON,
		row = ICON + ROW_PAD,
		-- Every entry this feed will ever hold, made once. A ring rather than a
		-- list that is trimmed: the four hundred and first drop overwrites the
		-- first rather than allocating a table and dropping another, so a feed
		-- in its steady state allocates nothing at all.
		ring = {},
		written = 0,
		offset = 0,
		visible = 0,
		rows = {},
		hovered = nil,
		width = 1,
		-- Every entry the paint is about to draw, filled once per paint and
		-- reused. A filtered feed cannot answer "the nth row" in one step, so
		-- the alternative is walking the ring once per row rather than once per
		-- paint, and a table per paint is garbage on the path a pull drives.
		window = {},
		-- How many entries the filter lets through, or nil for not counted
		-- since the last thing that could have moved it. Cached rather than
		-- walked per read, because Room, Sync and the tally all ask.
		matching = nil,
		chips = {},
		-- What ShapeRow is told, filled in by every resize and never rebuilt.
		geom = {},
		-- On screen until told otherwise. Feeds/Stream.lua writes this from the
		-- setting at login, and a feed built by anything else is one somebody is
		-- looking at.
		awake = true,
		stale = false,
	}, Feed)

	feed.frame = CreateFrame("Frame", nil, parent)

	for index = 1, feed.cap do
		feed.ring[index] = {}
	end

	BuildHeader(feed)

	for index = 1, MAX_ROWS do
		feed.rows[index] = BuildRow(feed, index)
	end

	if opts.chips then
		feed:BuildChips(opts.chips)
	end

	feed.bar = UI.ScrollBar(feed.frame, function(_, value)
		-- The bar is written back to on every arrival, and that write fires
		-- this. The latch is UI/Scroll.lua's and UI/Log.lua's, and it is here
		-- for the same reason: without it the write and the handler chase each
		-- other for a frame every time something drops.
		if feed.syncing then
			return
		end
		feed:ScrollTo(value)
	end)
	if feed.bar then
		feed.bar:SetPoint("BOTTOMRIGHT")
		feed.bar:Hide()
	end

	-- The strip as it was asked for: a title if there is one, chips if there
	-- are any. Last, because it anchors the scroll bar as well as the rows, and
	-- Feeds/Stream.lua writes both from settings a moment later.
	--
	-- Chrome rather than Dress, which is what this was called for an afternoon.
	-- Feeds/Stream.lua already has a Dress and it is the purse along the bottom;
	-- two methods of one name on two objects in one folder, one of them called
	-- on self and the other on self.feed, is a line nobody can read at a glance.
	feed:Chrome(feed.title ~= nil, #feed.chips > 0)
	return feed
end

--------------------------------------------------------------------------
-- The strip over the rows
--
-- Two settings and one strip. The title is a word over a column that already
-- says what it holds, which on the loot feed is an item icon, an item name in
-- the item's own quality colour and a stack size, and the chips beside it are
-- squares in the same quality colours. Nothing in that needs the word "Loot"
-- over it, and a window with no chrome on it is one more piece of the screen
-- given back to the game.
--
-- So both are switches and neither one implies the other. What they cannot be
-- is independent of the geometry: everything below the strip has to know
-- whether there is one, which is why one number is worked out here and Resize
-- and Sync read it rather than each deciding again.
--------------------------------------------------------------------------

function Feed:Chrome(titled, chipped)
	titled = (titled and self.heading) and true or false
	chipped = (chipped and #self.chips > 0) and true or false
	self.head = (titled or chipped) and (HEADER + RULE) or 0

	if self.heading then
		if titled then
			self.heading:Show()
		else
			self.heading:Hide()
		end
	end
	for index = 1, #self.chips do
		if chipped then
			self.chips[index]:Show()
		else
			self.chips[index]:Hide()
		end
	end

	-- The tally and the hairline are the strip rather than things on it, so
	-- they go with it entirely. A count floating over the first row with no
	-- rule under it reads as a number that belongs to that row.
	if self.head > 0 then
		self.tally:Show()
		self.rule:Show()
	else
		self.tally:Hide()
		self.rule:Hide()
	end

	-- The chips are the only reason a feed filters at all. Hidden, the filter
	-- goes with them: a column quietly refusing entries with no control on
	-- screen saying so is a feed that looks broken and cannot be argued with.
	self.filter = chipped and self.onFilter or nil
	self.matching = nil

	self.blank:ClearAllPoints()
	self.blank:SetPoint("TOPLEFT", self.frame, "TOPLEFT",
		(STRIPE + INSET) * self.unit, -(self.head + INSET) * self.unit)
	if self.bar then
		self.bar:ClearAllPoints()
		self.bar:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", 0, -self.head * self.unit)
		self.bar:SetPoint("BOTTOMRIGHT")
	end
	return true
end

--------------------------------------------------------------------------
-- The filter strip
--
-- A run of small coloured squares along the top of the feed, one per kind of
-- thing the feed can hold, each of them on or off. It is the answer to a
-- question a settings page answers badly: "not right now" is a thing you decide
-- while looking at the feed, and a window you have to open, find a page in and
-- close again is a window you stop opening.
--
-- **A chip is a mark in a colour.** No word on it and no word beside it. The
-- five quality chips are one glyph, a gem, in the game's own quality ramp read
-- left to right, which is a thing every player in this game already reads
-- without being told; a word on each would be five words of English in a feed
-- whose rows are localised.
--
-- The first version of this drew each chip as a rectangle of flat quality
-- colour and nothing else, and it was wrong in a way that is obvious the moment
-- you look at a screenshot rather than at the geometry: seven hard-edged colour
-- swatches in a row is a colour picker, and it looked like something that had
-- been left on the screen by mistake. Nothing else in this addon that you click
-- is a bare colour. An ability square, an aura square, a button in the panel
-- are all the same thing, a dark square with a hairline and a mark on it, and a
-- chip is that at chip size.
--
-- **Off is a dim mark, not a gone one.** A chip that hid itself would leave a
-- strip whose chips move about as you click them, and a chip that went grey
-- would lose the one thing saying which one it is. The square and its hairline
-- never move and never change, so the strip keeps its rhythm; what goes out is
-- the coloured mark on top of it.
--
-- **The filter is what is drawn, not what is kept.** Nothing here refuses an
-- entry at the door. Everything that drops is recorded and the chips decide
-- what the column shows, which is why turning one back on brings its history
-- with it rather than starting an empty list.
--
-- The caller hands over one table per chip, in the order they are drawn:
--
--   { color = , mark = , tip = , get = function() end, set = function(on) end }
--   { gap = true }   air, for the break between one run of chips and the next
--
-- `mark` is the letter the glyph face draws its mark on. See
-- scripts/bake-glyphs.sh for which letter is which mark and why the letter
-- matters on a client that will not take the font.
--
-- `tip` is a string, or a function answering one for a chip whose sentence is
-- not knowable until somebody hovers it.
--------------------------------------------------------------------------

local function PaintChip(chip)
	local on = chip.get() and true or false
	if chip.lit == on then
		return false
	end
	chip.lit = on
	-- The mark, not the square. The ground and its hairline are furniture and
	-- stay exactly where they are, so a strip of chips keeps its rhythm however
	-- many of them are off; what goes out is the coloured thing on top.
	chip.mark:SetAlpha(on and 1 or CHIP_OFF)
	return true
end

function Feed:BuildChips(specs)
	local unit = self.unit
	local x = INSET

	for index = 1, #specs do
		local spec = specs[index]
		if spec.gap then
			x = x + CHIP_BREAK
		else
			local chip = CreateFrame("Button", nil, self.frame)
			chip:SetSize(CHIP * unit, CHIP * unit)
			chip:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x * unit,
				-math.floor((HEADER - CHIP) / 2) * unit)

			-- A square of the addon's own furniture with a mark on it, which is
			-- what every other thing in here you can click looks like: an
			-- ability square, an aura square, a button in the panel. It was a
			-- rectangle of flat quality colour, and seven of those in a row read
			-- as a colour picker somebody had left on the screen.
			chip.bg = ns.Fill(chip, "BACKGROUND", C.control[1], C.control[2], C.control[3], 1)
			chip.bg:SetAllPoints()
			chip.edges = ns.Outline(chip, C.edge[1], C.edge[2], C.edge[3], 1)
			ns.EdgeSize(chip.edges, ns.Pixel(chip))

			-- The glyph face, so the mark is a gem or a quest bang rather than a
			-- shape this file drew out of rectangles. UI/Text.lua falls the
			-- whole thing back to Arial Narrow on a client that refuses the
			-- font, and scripts/bake-glyphs.sh picked the three letters so that
			-- what comes back is still a mark: `*`, `!` and `$`.
			-- The size raw, not in units. Every measurement in this file is a
			-- design pixel multiplied up by the zoom, and a font size is the one
			-- thing that is not: inside a frame ns.UI.Adopt has taken onto the
			-- grid, a font size already is a pixel height. Multiplied, this
			-- asked UI.GlyphFont for 26.25, SetFont refused the fraction,
			-- GetFont came back nil and the chip drew nothing at all. Every
			-- other caller of UI.Glyph in the addon passes ns.UI.Metric.glyph
			-- and this one now reads like them.
			chip.mark = UI.Glyph(chip, CHIP_MARK, spec.color, "CENTER")
			chip.mark:SetPoint("CENTER")
			chip.mark:SetText(spec.mark)

			chip.get, chip.set, chip.tip = spec.get, spec.set, spec.tip
			chip:SetScript("OnClick", function(this)
				this.set(not this.get())
				PaintChip(this)
				self:Refilter()
			end)
			chip:SetScript("OnEnter", function(this)
				UI.Tint(this.bg, C.hover)
				-- Opened above rather than beside. A tooltip hung off the right
				-- of a sixteen pixel square lands underneath the cursor that
				-- opened it, because the pointer's hotspot is its top left
				-- corner and the arrow itself hangs down and to the right. On a
				-- feed row, which is the width of the window, the same anchor
				-- is fine and this would throw the box up over the rows.
				-- Called rather than read where the caller gave a function. A
				-- chip that names a quality names it in the client's own
				-- language, and the client's own language is a global that is
				-- not reliably in place while the addon's files are still
				-- loading, which is the same trap Feeds/Loot.lua builds its
				-- loot patterns at login to avoid.
				local tip = this.tip
				ns.Tip.Open(this, { kind = "note",
					lines = { type(tip) == "function" and tip() or tip } }, true)
			end)
			chip:SetScript("OnLeave", function(this)
				UI.Tint(this.bg, C.control)
				ns.Tip.Close()
			end)
			UI.PassCamera(chip)
			PaintChip(chip)

			self.chips[#self.chips + 1] = chip
			x = x + CHIP + CHIP_GAP
		end
	end
	return #self.chips
end

-- One chip, for scripts/harness.lua and for a macro. Handed out for the reason
-- Feed:Row is: "clicking the grey chip took the greys off the column" is a
-- claim the harness has to be able to make by clicking, and reaching into this
-- file's own list to make it would be asserting its spelling.
function Feed:Chip(index)
	return self.chips[index]
end

-- The chips repainted from the settings behind them, which is what the panel
-- calls after a check box has moved one of them from the other end.
function Feed:Chipped()
	for index = 1, #self.chips do
		PaintChip(self.chips[index])
	end
	return self:Refilter()
end

-- The filter said something different from what it last said. The count is
-- thrown away rather than adjusted, because what moved is the answer for every
-- entry at once, and the offset is clamped after the recount rather than before
-- it: turning a chip off can leave you scrolled past the end of a list that has
-- just become shorter than the screen.
function Feed:Refilter()
	self.matching = nil
	if self.offset > self:Room() then
		self.offset = self:Room()
	end
	return self:Paint()
end

--------------------------------------------------------------------------
-- What is in it
--
-- The ring counts from the newest backwards, because that is the only order a
-- feed is ever read in: row one is the newest, row two is the one before it,
-- and the offset is how many have been scrolled past.
--------------------------------------------------------------------------

-- How many entries the feed is holding, filter or no filter. This is what the
-- ring has in it rather than what the column is drawing, and the two are
-- different numbers the moment a chip goes off.
function Feed:Count()
	return math.min(self.written, self.cap)
end

-- The nth entry counting back through the ring, where zero is the one that
-- arrived last. Filter or no filter, and therefore not what row n draws.
function Feed:Held(n)
	if n < 0 or n >= self:Count() then
		return nil
	end
	return self.ring[((self.written - 1 - n) % self.cap) + 1]
end

-- How many of them the chips let through, which is what the column is a view
-- of and what the scrollbar measures against.
--
-- Cached, and the cache is thrown away rather than kept in step. A filter that
-- has just changed has changed the answer for every entry at once, and an
-- arrival is one comparison on the entry that arrived. One walk of at most four
-- hundred table reads is the price of a chip click, which is a gesture.
function Feed:Shown()
	if not self.filter then
		return self:Count()
	end
	if self.matching then
		return self.matching
	end

	local count = 0
	for back = 0, self:Count() - 1 do
		if self.filter(self:Held(back)) then
			count = count + 1
		end
	end
	self.matching = count
	return count
end

-- The nth newest entry the filter lets through, where zero is the newest of
-- them. This is what row n draws and what the offset counts in.
--
-- The unfiltered case is the one line it always was, because most feeds have no
-- filter and the one that does spends most of its life with every chip on. The
-- filtered case walks, which is why Paint does not call this per row: see
-- Feed:Window.
function Feed:At(n)
	if not self.filter then
		return self:Held(n)
	end
	if n < 0 then
		return nil
	end

	local seen = 0
	for back = 0, self:Count() - 1 do
		local slot = self:Held(back)
		if self.filter(slot) then
			if seen == n then
				return slot
			end
			seen = seen + 1
		end
	end
	return nil
end

-- The run of entries one paint is about to draw, written into a table this feed
-- owns and handed back with how many of its slots were filled.
--
-- One walk rather than Feed:At per row. Twenty four rows against four hundred
-- entries is nine thousand comparisons done as At and four hundred done as
-- this, and the arithmetic does not change: the offset is skipped and then the
-- next `visible` matches are kept.
function Feed:Window()
	local window, want = self.window, self.visible

	if not self.filter then
		for index = 1, want do
			window[index] = self:Held(self.offset + index - 1)
		end
		return window, want
	end

	local skipped, filled = 0, 0
	for back = 0, self:Count() - 1 do
		if filled >= want then
			break
		end
		local slot = self:Held(back)
		if self.filter(slot) then
			if skipped < self.offset then
				skipped = skipped + 1
			else
				filled = filled + 1
				window[filled] = slot
			end
		end
	end
	for index = filled + 1, want do
		window[index] = nil
	end
	return window, want
end

-- The slot the next entry goes in, wiped and handed over for the caller to
-- fill. The feed owns it: filling it and then not calling Push leaves it to be
-- wiped again by the next caller, and holding on to it past a Push is holding a
-- table the ring will write over.
--
-- Two calls rather than one that takes the fields, because the fields differ
-- per feed. A loot row is an item and a stack size; a combat row is a spell, a
-- number and four things only the tooltip reads. Passing either as arguments
-- would fix one feed's shape into this file, and passing a table would
-- allocate one per event on a path the combat log drives.
function Feed:Entry()
	local slot = self.ring[(self.written % self.cap) + 1]
	-- Past the cap this slot is holding the oldest entry, and wiping it is the
	-- moment that entry leaves the feed. If the filter was letting it through,
	-- the count goes down by it here, because in a line's time there will be
	-- nothing left to ask.
	if self.matching and self.written >= self.cap and self.filter(slot) then
		self.matching = self.matching - 1
	end
	for key in pairs(slot) do
		slot[key] = nil
	end
	return slot
end

-- Make the filled slot the newest, and redraw.
--
-- The offset moves with it when you are reading history. Everything below the
-- top has just been pushed one row down the list, so leaving the offset alone
-- would scroll the feed under your eyes every time a mob died. At the top,
-- where the offset is zero, the new entry simply arrives, which is the whole
-- point of being at the top.
function Feed:Push()
	local slot = self.ring[(self.written % self.cap) + 1]
	slot.at = GetTime()
	self.written = self.written + 1
	-- One comparison rather than a recount. What this entry pushed out of the
	-- ring was taken off the count in Feed:Entry, where it was still there to
	-- be asked about.
	if self.matching and self.filter(slot) then
		self.matching = self.matching + 1
	end

	if self.offset > 0 and self.offset < self:Room() then
		self.offset = self.offset + 1
	end

	self:Paint()
	return slot
end

-- A break in the timeline rather than a thing that happened.
--
--   kind      what this marker is. Nothing here reads it; it is carried so the
--             tooltip can say which of the two it is looking at.
--   label     the word on the band
--   trailing  the right hand side, which at the end of a fight is how long it
--             lasted and at the start of one is nothing
--   band      the band's colour, and the whole of how a marker is told apart
--             from an entry at a glance
--
-- Loose arguments rather than a table, for the reason Feed:Entry is two calls:
-- a marker arrives on the same event path a pull does.
function Feed:Mark(kind, label, trailing, band)
	local slot = self:Entry()
	slot.mark = kind or true
	slot.name = label or ""
	slot.amount = trailing or ""
	slot.stripe = band or C.chrome
	return self:Push()
end

function Feed:Clear()
	self.written, self.offset, self.matching = 0, 0, nil
	self:Paint()
	return true
end

--------------------------------------------------------------------------
-- Where you are in it
--------------------------------------------------------------------------

-- How many entries are off the bottom of the view, which is how far the offset
-- is allowed to go.
function Feed:Room()
	return math.max(0, self:Shown() - self.visible)
end

function Feed:Live()
	return self.offset <= 0
end

function Feed:Offset()
	return self.offset
end

-- One drawn row, for scripts/harness.lua and for a macro.
--
-- Handed out for the reason Meter/Window.lua hands out a pane: the harness has
-- to measure what was actually drawn, and the alternative is this file
-- publishing its whole pool or the harness asserting against the entry list,
-- which would be asserting that the data is right rather than that it reached
-- the screen. Those are different claims and the second one is the one a
-- screenshot would show.
function Feed:Row(index)
	return self.rows[index]
end

function Feed:ScrollTo(value)
	local room = self:Room()
	local want = math.max(0, math.min(math.floor((value or 0) + 0.5), room))
	if want == self.offset then
		return false
	end
	self.offset = want
	self:Paint()
	return true
end

function Feed:Scroll(rows)
	return self:ScrollTo(self.offset + rows)
end

function Feed:ToTop()
	return self:ScrollTo(0)
end

--------------------------------------------------------------------------
-- Size, and whether it answers the mouse
--------------------------------------------------------------------------

-- The bar column is reserved whether or not the bar is showing, which is the
-- rule UI/Scroll.lua and UI/Log.lua both state: handing the width back when the
-- content fits would rewrap the rows, which can make them not fit, which brings
-- the bar back. A layout that can argue with itself is a layout that flickers.
-- One row given the geometry the resize worked out, which is every number about
-- a row that is not the entry on it.
--
-- Its own function because the resize now decides five things rather than
-- three: the icon is a setting, the row height follows the icon, and the name
-- starts after both. Twenty four rows of that inside the arithmetic that
-- produced it is a function nobody reads to the end.
local function ShapeRow(feed, row, index, geom)
	local unit = feed.unit

	row:SetSize(geom.content * unit, feed.row * unit)
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", feed.frame, "TOPLEFT", 0,
		-(feed.head + (index - 1) * (feed.row + ROW_GAP)) * unit)

	row.icon:SetSize(feed.icon * unit, feed.icon * unit)
	ns.EdgeSize(row.mark.edges, ns.Pixel(row.mark))

	row.name:ClearAllPoints()
	row.name:SetPoint("LEFT", row, "LEFT",
		(STRIPE + INSET + feed.icon + GUTTER) * unit, 0)
	row.name:SetWidth(geom.name * unit)
	row.amount:SetWidth(AMOUNT * unit)
	row.caption:SetWidth(geom.caption * unit)

	row.noted = geom.note > 0
	if row.noted then
		row.note:SetWidth(geom.note * unit)
	end
	-- Written from here rather than left to the repaint, because whether
	-- there is a middle column at all is decided by the width and a row that
	-- is not repainting is a row that would keep the last answer.
	if row.noted and not row.shownMark then
		row.note:Show()
	else
		row.note:Hide()
	end

	-- What the stripe is on an entry and what it becomes on a marker, held
	-- on the row so the repaint can swap between them without knowing the
	-- feed's width.
	row.rib = STRIPE * unit
	row.band = geom.content * unit
end

-- Everything a setting can move about a column: how wide it is, how many rows
-- it draws and how large the picture on each of them is.
--
-- The icon is the third argument rather than a fourth call, because the row
-- height, the name's left edge and the frame's own height all follow from it
-- and a feed that learned about a new icon size in a separate pass would be a
-- feed with two of the three written and one still on the old number.
function Feed:Resize(width, rows, icon)
	local unit = self.unit
	rows = math.max(1, math.min(rows or 1, MAX_ROWS))
	icon = math.max(UI.FEED_ICON_LOW, math.min(icon or ICON, UI.FEED_ICON_HIGH))

	self.width = width
	self.visible = rows
	self.icon = icon
	self.row = icon + ROW_PAD

	local height = self.head + rows * (self.row + ROW_GAP) - ROW_GAP
	self.frame:SetSize(width * unit, height * unit)

	local content = math.max(width - M.bar - M.gutter, 1)
	if self.rule then
		self.rule:SetWidth(width * unit)
	end

	-- The three text columns, decided here and written to every row, so the
	-- names line up down the feed and so do the numbers. The number column is
	-- fixed and the other two share what is left; the middle one never takes
	-- more than half of that, because a feed narrowed to its minimum has to
	-- leave the name enough room to still be a name.
	local free = content - (STRIPE + INSET + icon + GUTTER) - INSET - AMOUNT - PAD
	local note = 0
	if self.note > 0 then
		note = math.max(0, math.min(self.note, math.floor((free - PAD) / 2)))
	end

	-- One table, kept and written over. A resize is not on a ticker, but it is
	-- on the rescale path and on every stepper click, and a table per click is
	-- garbage for nothing when the fields are the same five every time.
	local geom = self.geom
	geom.content = content
	geom.note = note
	geom.name = math.max(free - (note > 0 and note + PAD or 0), 1)
	geom.caption = math.max(content - STRIPE - INSET * 2 - AMOUNT - PAD, 1)

	for index = 1, MAX_ROWS do
		local row = self.rows[index]
		ShapeRow(self, row, index, geom)
		if index > rows then
			row.shownEntry = nil
			row:Hide()
		end
	end

	-- The offset can be past the end after a shrink, which is a feed that draws
	-- a screen of nothing at the bottom of its own history.
	if self.offset > self:Room() then
		self.offset = self:Room()
	end

	self:MouseRows()
	self:Paint()
	return width * unit, height * unit
end

-- Whether the rows take the mouse at all.
--
-- A setting rather than always on, and the note in Meter/Window.lua is the
-- reason: a mouse enabled frame swallows every button that lands on it, and a
-- feed is a tall rectangle sitting where a right button drag to turn the camera
-- starts. ns.UI.PassCamera hands those two buttons back where the client will
-- take them, and where it will not this is the switch that gets the camera
-- back at the price of the tooltips.
-- Which rows take the mouse: the ones being drawn, and only while the setting
-- is on. Its own function because two things move it and each would otherwise
-- leave the other stale. Turning the setting off has to reach every row, and
-- so does growing the feed from eight rows to twelve, and a Mouse that returned
-- early because the setting had not changed would leave the four new rows
-- inert. That is a bug you find by hovering the bottom of a feed you have just
-- made taller, which is to say not for weeks.
function Feed:MouseRows()
	for index = 1, MAX_ROWS do
		self.rows[index]:EnableMouse(self.mouse and index <= self.visible or false)
	end
	-- And the chips go with them. The setting says this feed is a picture, and
	-- a picture with seven clickable squares on it is a feed that still takes
	-- the button somebody turned the setting off to get back.
	for index = 1, #self.chips do
		self.chips[index]:EnableMouse(self.mouse and true or false)
	end
end

function Feed:Mouse(on)
	on = on and true or false
	if self.mouse == on then
		return false
	end
	self.mouse = on
	self:MouseRows()

	if type(self.frame.EnableMouseWheel) == "function" then
		self.frame:EnableMouseWheel(on)
		if on then
			self.frame:SetScript("OnMouseWheel", function(_, delta)
				-- Down the wheel is down the list, which is backwards in time.
				-- Shift is the whole way, the same shortcut UI/Log.lua keeps
				-- from the client's own chat.
				if IsShiftKeyDown and IsShiftKeyDown() then
					self:ScrollTo(delta > 0 and 0 or self:Room())
					return
				end
				self:Scroll(-delta * WHEEL_ROWS)
			end)
		else
			self.frame:SetScript("OnMouseWheel", nil)
		end
	end

	if not on then
		self:Leave()
	end
	return true
end

--------------------------------------------------------------------------
-- The mouse
--------------------------------------------------------------------------

function Feed:Enter(index)
	local row = self.rows[index]
	if not row then
		return false
	end
	self.hovered = index
	row.glow:Show()

	local entry = row.shownEntry
	-- What the row was showing when this tooltip was filled, so Paint can tell a
	-- repaint that moved the entry under the cursor from one that did not. Both
	-- halves: the ring hands the same table back a full lap later, and the push
	-- time is the only thing that tells that apart from nothing having changed.
	self.hoveredEntry = entry
	self.hoveredAt = entry and entry.at

	if not entry or not self.onTooltip then
		return false
	end
	return ns.Tip.Open(row, self.onTooltip(entry))
end

function Feed:Leave()
	if self.hovered then
		local row = self.rows[self.hovered]
		if row then
			row.glow:Hide()
		end
		self.hovered = nil
	end
	self.hoveredEntry, self.hoveredAt = nil, nil
	ns.Tip.Close()
	return true
end

--------------------------------------------------------------------------
-- Painting
--
-- Every write is guarded on what the row already carries. This is not a ticker,
-- so the guards are not buying frames off a hot path; they are buying the case
-- a feed is actually in most of the time, which is one entry arriving at the
-- top of a column that is otherwise exactly what it already was. Without them
-- every drop would rewrite ten icons, twenty strings and ten colours to move
-- one row down by one.
--------------------------------------------------------------------------

local function Blank(row)
	if row.shownEntry ~= nil then
		row.shownEntry = nil
		row:Hide()
	end
end

-- A row turned from a thing that happened into a break in the timeline, or
-- back.
--
-- A marker drops everything a row uses to say what happened and its stripe
-- becomes the whole row. That is a shape an entry cannot take, and it has to
-- be, because the one thing worse than not marking where a fight started is a
-- mark that reads as a hit for nothing.
--
-- The fields the swap invalidates are cleared with it. Without that a marker
-- whose word matched the name already on the row would keep the row's own
-- string: a guard holding on a value that is right and a widget that is not.
--
-- Its own function because PaintRow reached thirty four branches and the gate
-- is thirty. This is the half of it that runs about twice a fight; everything
-- left in PaintRow runs on every arrival.
local function Marked(row, mark)
	if row.shownMark == mark then
		return false
	end

	row.shownMark = mark
	row.shownName, row.shownColor, row.shownIcon, row.shownNote = nil, nil, nil, nil
	row.stripe:SetWidth(mark and row.band or row.rib)
	if mark then
		row.icon:Hide()
		row.name:Hide()
		row.note:Hide()
		row.caption:Show()
	else
		row.icon:Show()
		row.name:Show()
		row.caption:Hide()
		if row.noted then
			row.note:Show()
		end
	end
	return true
end

local function PaintRow(row, entry, faded)
	if row.shownEntry ~= entry or not row:IsShown() then
		row.shownEntry = entry
		row:Show()
	end

	local mark = entry.mark or false
	Marked(row, mark)

	local label = mark and row.caption or row.name

	if not mark and row.shownIcon ~= entry.icon then
		row.shownIcon = entry.icon
		row.icon:SetTexture(entry.icon)
	end

	-- The ring, which on this feed means a quest item and on any other feed
	-- means whatever the capture file decided to say with it. A marker has no
	-- icon, so it can never have one round it.
	local ring = (not mark) and entry.ring or nil
	if row.shownRing ~= ring then
		row.shownRing = ring
		if ring then
			ns.Recolor(row.mark.edges, ring)
			row.mark:Show()
		else
			row.mark:Hide()
		end
	end

	if row.shownName ~= entry.name then
		row.shownName = entry.name
		label:SetText(entry.name or "")
	end

	if not mark and row.shownNote ~= entry.note then
		row.shownNote = entry.note
		row.note:SetText(entry.note or "")
	end

	if row.shownAmount ~= entry.amount then
		row.shownAmount = entry.amount
		row.amount:SetText(entry.amount or "")
	end

	local color = entry.color or C.text
	if row.shownColor ~= color then
		row.shownColor = color
		label:SetTextColor(color[1], color[2], color[3])
	end

	local tone = entry.tone or C.text
	if row.shownTone ~= tone then
		row.shownTone = tone
		row.amount:SetTextColor(tone[1], tone[2], tone[3])
	end

	local stripe = entry.stripe or color
	if row.shownStripe ~= stripe then
		row.shownStripe = stripe
		row.stripe:SetColorTexture(stripe[1], stripe[2], stripe[3], stripe[4] or 1)
	end

	local alpha = faded and FADE or 1
	if row.shownAlpha ~= alpha then
		row.shownAlpha = alpha
		row:SetAlpha(alpha)
	end
end

-- Whether anybody can see this, and the whole reason a hidden feed is cheap.
--
-- Everything above the repaint still runs while it is asleep: an arrival wipes
-- a ring slot, fills it and pushes it, and that is a handful of table writes.
-- What does not run is Feed:Paint, and Paint is the expensive half by an order
-- of magnitude. It writes five regions on every one of up to twenty four rows
-- on every arrival, and in a pull arrivals come faster than frames do. A column
-- nobody is looking at, redrawing itself two hundred times a second, is the
-- clearest case of work nobody asked for in the addon.
--
-- The skipped redraw is not lost. Anything that would have painted while asleep
-- leaves the feed stale, and waking it paints once, so what comes back is the
-- list as it is now rather than as it was when it went away.
function Feed:Awake(on)
	on = on and true or false
	if self.awake == on then
		return false
	end
	self.awake = on
	if on and self.stale then
		self.stale = false
		self:Paint()
	end
	return true
end

function Feed:Paint()
	if not self.awake then
		self.stale = true
		return false
	end

	local count, shown = self:Count(), self:Shown()
	local room = self:Room()

	-- Show and Hide rather than SetShown. Every frame on both clients answers
	-- SetShown and this is a font string, which is a region rather than a frame,
	-- and nothing installed here proves a region takes it on 2.5.6. The two
	-- calls are the same write and cannot be refused.
	local blank = shown == 0 and (self.empty or "") ~= ""
	if self.blank and self.shownBlank ~= blank then
		self.shownBlank = blank
		if blank then
			self.blank:Show()
		else
			self.blank:Hide()
		end
	end

	local window = self:Window()
	for index = 1, self.visible do
		local entry = window[index]
		if entry then
			-- The last row fades only while there is something under it to fade
			-- into. At the bottom of the history there is nothing below and a
			-- dimmed final row would be saying so falsely.
			PaintRow(self.rows[index], entry,
				index == self.visible and self.offset < room)
		else
			Blank(self.rows[index])
		end
	end
	for index = self.visible + 1, MAX_ROWS do
		Blank(self.rows[index])
	end

	-- The count, and what a filter is keeping off the screen.
	--
	-- Two numbers rather than one whenever they differ, because a chip you left
	-- off an hour ago is invisible from the column itself: a feed showing four
	-- rows when forty things dropped looks broken, and "4/40" is the whole
	-- explanation in four glyphs.
	if self.tally then
		local held = ""
		if shown < count then
			held = ("%d/%d"):format(shown, count)
		elseif count > 0 then
			held = tostring(count)
		end
		if self.shownTally ~= held then
			self.shownTally = held
			self.tally:SetText(held)
		end
	end

	-- The row under the cursor may have been repainted with a different entry on
	-- it, and then the tooltip beside it is about something that has moved on.
	-- It is reopened rather than closed, because a tooltip vanishing when a mob
	-- dies somewhere else is worse than one that follows the row it is on.
	--
	-- Guarded, and this guard buys more than the usual one. Filling a tooltip
	-- builds a table and a string or two, which a hover can afford; reopening it
	-- unconditionally made that one fill per combat log event for as long as the
	-- cursor rested anywhere on the feed. The row under the cursor mostly does
	-- not move: the mouse is on row seven and the arrival lands on row one.
	if self.hovered and self.hovered <= self.visible then
		local row = self.rows[self.hovered]
		if row.shownEntry ~= self.hoveredEntry
			or (row.shownEntry and row.shownEntry.at ~= self.hoveredAt) then
			self:Enter(self.hovered)
		end
	end

	self:Sync()
	return true
end

-- Puts the bar back in step with the offset. Called after anything that could
-- move either, which is an arrival, a scroll and a resize.
function Feed:Sync()
	local bar = self.bar
	if not bar then
		return false
	end

	local room = self:Room()
	if room <= 0 then
		bar:Hide()
		return false
	end

	local height = self.visible * (self.row + ROW_GAP) - ROW_GAP
	local size = math.max(M.thumb,
		UI.Round(self.frame, height * self.unit * self.visible / math.max(self:Shown(), 1)))
	bar.thumb:SetSize(M.bar, size)

	self.syncing = true
	bar:SetMinMaxValues(0, room)
	bar:SetValue(self.offset)
	self.syncing = nil
	bar:Show()
	return true
end

--------------------------------------------------------------------------

-- One line for a status command or a panel note. What is worth saying is where
-- you are in it, because a feed that looks stuck is nearly always a feed you
-- scrolled down an hour ago and left there.
function Feed:Describe()
	local count, shown = self:Count(), self:Shown()
	if count == 0 then
		return "empty"
	end

	local line = ("%d held"):format(count)
	if shown < count then
		line = line .. (", %d of them drawn and the rest filtered out")
			:format(shown)
	end
	if not self:Live() then
		line = line .. (", scrolled back %d"):format(self.offset)
	end
	return line
end
