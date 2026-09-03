local ADDON, ns = ...

local Window = {}
ns.SpellWindow = Window

local UI = ns.UI
local C, M = UI.Color, UI.Metric
local Read = ns.BookRead

--------------------------------------------------------------------------
-- The spell book
--
-- Every spell you know, one row each, with its ranks folded behind one
-- button.
--
-- **That is the whole argument.** The client's own book lists every rank of
-- every spell as its own entry, twelve to a page, so a warrior at sixty pages
-- through Rend six times and Battle Shout seven to find Sunder Armor. Here a
-- spell is one row: the square, the name, and the rank the square is holding
-- on the right. Where you know more than one rank there is a fold-out beside
-- it, and picking a rank there is what the square then casts and what a drag
-- off it puts on a bar. The pick is written down per character, so the rank
-- you set the square to is the rank it opens on tomorrow.
--
-- **It replaces the client's window rather than sitting beside it.**
-- Blizzard.lua puts the client's frame in the attic and takes the P key,
-- behind the one switch on the page where every other Blizzard frame this
-- addon replaces is switched.
--
-- **Every square is a secure button, and everything below that says `secure`
-- or `InCombatLockdown` is there for that one sentence.** A click on a spell
-- casts it, casting is protected, and the only way an addon gets a protected
-- act out of a click is a button built on the secure template. The cost is
-- the one the character sheet already pays: a window with protected frames in
-- it cannot be shown, hidden, sized or repainted by ordinary Lua in a fight.
-- So the key is bound to a secure button whose snippet shows and hides the
-- window, the close cross is one, and everything that writes a square, the
-- rank picked or the book changing, waits for the fight to end and says so.
-- Blizzard's own book does all of that in a fight because Blizzard's code is
-- allowed to.
--
-- **Nothing scrolls.** A tab is laid out in columns and the window is sized
-- to the tallest tab, the way the talent window is sized to the tallest tree.
-- A scroll view would be the canvas the squares hang off moving under the
-- wheel, and moving a frame with protected children is refused in combat;
-- a window whose wheel works out of a fight and is refused in one is a
-- window that feels broken. Grouping the ranks is what makes the count small
-- enough for this: no tab on any class is more than a screen of rows.
--
-- Nothing here is on a ticker. The window paints when it opens and when the
-- client says the book changed, and a window nobody has open is not painted
-- at all.
--
-- **The book is read on the way up, not at login.** Reading it is four client
-- calls per entry over every rank of every spell you know, which on a warrior
-- at sixty is about eight hundred, and it ran at login and again on every
-- SPELLS_CHANGED whether or not anybody had ever opened this. SPELLS_CHANGED
-- marks the book stale now and the first paint after that is what pays for it.
-- A session that never presses P reads the book never.
--
-- The frames are a different question and they stay at login, because the key
-- has to work in a fight. The snippet below is handed the window as a frame
-- reference, a snippet may only touch what it has been given, and neither the
-- window nor the reference can be made in combat. A book built on first press
-- would be a key that does nothing the first time it is pressed in a pull.
--------------------------------------------------------------------------

-- The rows go in columns of this many, and the window is as wide as that
-- many columns of the row width below. Two is the client's own count and it
-- is the right one: a row is a square, a name and a rank, and three of those
-- across is names cut short.
local COLUMNS = 2

-- One row of the grid: a square, a name, the rank on the right and the
-- fold-out past it. Wide enough that the longest name on any class, which is
-- the shaman's and the priest's, sits beside its rank without touching.
local ROW_WIDTH = 236

-- The air between two columns, and under the tab strip before the grid.
local BETWEEN = 20

-- One row's pitch: the square, and the air to the next square.
local PITCH = UI.SLOT + 6

-- The fold-out button: a square the height of a control.
local FOLD = M.control

local window, tabs, foot, key, grid
local rows = {}

-- What the book read last time, and which tab of it is up.
local book = {}
local viewing = 1

-- The tallest tab, in rows per column, so the window can be sized once for
-- all of them and does not jump when you change tab.
local deepest = 1

-- Whether a fight refused something. One flag rather than a queue, because
-- everything deferred here ends in the same pass: fit the window and paint
-- the tab that is up.
local pending = false

-- Whether the book on file is older than the client's. True until something
-- has read it, so the first read is the first paint rather than login.
local stale = true

--------------------------------------------------------------------------
-- Which rank a square holds
--
-- The one you picked, written down per character under the spell's name, or
-- the highest you know. Written as the ordinal in the list rather than the
-- rank line, because the line is localised and the ordinal is not. A pick
-- past the end of the list, which a client can produce by forgetting a rank,
-- falls back to the top the way an unset one does.
--------------------------------------------------------------------------

local function Chosen(spell)
	local picks = ns.dbc.spellRanks
	local pick = picks and picks[spell.name]
	local count = #spell.ranks
	if type(pick) == "number" and pick >= 1 and pick < count then
		return pick
	end
	return count
end

local function Remember(spell, pick)
	local picks = ns.dbc.spellRanks
	if type(picks) ~= "table" then
		picks = {}
		ns.dbc.spellRanks = picks
	end
	-- The top rank is the default, so choosing it is choosing nothing, and
	-- nothing is what gets written: a table of every spell at its best rank
	-- is a table that says the same as an empty one and is read every paint.
	if pick >= #spell.ranks then
		picks[spell.name] = nil
	else
		picks[spell.name] = pick
	end
end

--------------------------------------------------------------------------
-- The hover, the press, the drag and the fold-out
--------------------------------------------------------------------------

local function Subject(row)
	local spell, rank = row.spell, row.spell.ranks[row.pick]
	local lines = {}
	if #spell.ranks > 1 then
		lines[#lines + 1] = { ("%s of %d you know"):format(rank.label, #spell.ranks) }
	end
	if spell.passive then
		lines[#lines + 1] = { "Always on. Nothing to cast and nothing to drag.", color = C.dim }
	elseif #spell.ranks > 1 then
		lines[#lines + 1] = { "Click to cast, drag onto a bar. The button beside the rank picks another.", color = C.hint }
	else
		lines[#lines + 1] = { "Click to cast, drag onto a bar.", color = C.hint }
	end
	return { kind = "spell", spell = rank.id, title = spell.name, lines = lines }
end

local function OnEnter(square)
	UI.Tint(square.bg, C.hover)
	if square.row.spell then
		ns.Tip.Open(square, Subject(square.row), nil, UI.Tooltip.BESIDE)
	end
end

local function OnLeave(square)
	UI.Tint(square.bg, C.sunken)
	ns.Tip.Close()
end

-- Before the secure half of the click. A click on a square is a cast, and a
-- fold-out still open over the window is a list that has nothing to do with
-- the spell you just cast.
local function PreClick()
	UI.CloseDropdown()
end

-- Onto the cursor, which is what a bar takes. Refused in a fight because the
-- pickup is, and said out loud because a drag that does nothing looks like a
-- square that is not one.
local function OnDragStart(square)
	local row = square.row
	if not row.spell or row.spell.passive then
		return false
	end
	if InCombatLockdown() then
		ns.Print("a spell cannot be picked up in a fight.")
		return false
	end
	return Read.Pickup(row.spell.ranks[row.pick])
end

-- The secure half of a square: what a press casts. Refused in a fight, which
-- is where every SetAttribute is, and the flag puts it right when the fight
-- ends. Cleared rather than left on a square whose spell is passive, so a
-- press on Enrage does not cast whatever the row held last.
local function Arm(row)
	local spell = row.spell
	if InCombatLockdown() then
		pending = true
		return false
	end
	if not spell or spell.passive then
		row.square:SetAttribute("type", nil)
		row.square:SetAttribute("spell", nil)
	else
		row.square:SetAttribute("type", "spell")
		row.square:SetAttribute("spell", Read.Cast(spell, spell.ranks[row.pick]))
	end
	return true
end

local function PaintRow(row)
	local spell = row.spell
	local rank = spell.ranks[row.pick]
	UI.SlotPaint(row.square, spell.icon, nil, nil, false)
	row.name:SetText(spell.name)
	row.rank:SetText(rank.label)
	row.fold:SetShown(#spell.ranks > 1)
	if #spell.ranks > 1 then
		row.rank:SetPoint("RIGHT", row.fold, "LEFT", -M.rowGap, 0)
	else
		row.rank:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	end
end

local function Pick(row, value)
	Remember(row.spell, value)
	row.pick = value
	PaintRow(row)
	if not Arm(row) then
		ns.Print(("%s goes onto the square when the fight ends."):format(row.spell.ranks[value].label))
	end
	Window.Foot()
end

-- Every rank you know, highest first, the one on the square marked.
local function Options(row)
	local options = {}
	local spell = row.spell
	for at = #spell.ranks, 1, -1 do
		local text = spell.ranks[at].label
		if at == row.pick then
			text = text .. ", on the square"
		end
		options[#options + 1] = { value = at, text = text }
	end
	return options
end

local function OnFold(button)
	local row = button.row
	local open = UI.Dropdown()
	if open and open.owner == button then
		UI.CloseDropdown()
		return false
	end
	UI.OpenDropdown(window.frame, button, Options(row), function(value)
		Pick(row, value)
	end)
	return true
end

--------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------

local function Row(index)
	local row = rows[index]
	if row then
		return row
	end
	row = CreateFrame("Frame", nil, grid)
	row:SetSize(ROW_WIDTH, UI.SLOT)

	-- The square. Two edges, and they are two separate switches: the
	-- registration is what the mouse obeys, and it is the up edge because a
	-- square you can drag a spell off must not cast on the press that starts
	-- the drag. Which edge a bound key fires on is the attribute, said out
	-- loud rather than left to the player's settings; Buttons/Bars.lua carries
	-- the proof.
	local square = CreateFrame("Button", nil, row, "SecureActionButtonTemplate")
	square:SetSize(UI.SLOT, UI.SLOT)
	square:SetPoint("LEFT")
	UI.Dress(square, UI.SLOT)
	square:RegisterForClicks("AnyUp")
	square:SetAttribute("useOnKeyDown", false)
	square:RegisterForDrag("LeftButton")
	square:SetScript("PreClick", PreClick)
	square:SetScript("OnDragStart", OnDragStart)
	square:SetScript("OnEnter", OnEnter)
	square:SetScript("OnLeave", OnLeave)
	UI.PassCamera(square)
	square.row = row
	row.square = square

	row.fold = UI.Button(row, { glyph = true, label = "v", width = FOLD, height = FOLD, onClick = OnFold })
	row.fold:SetPoint("RIGHT")
	row.fold.row = row

	row.rank = UI.Label(row, M.small, C.dim, "RIGHT", UI.FLAT)
	UI.Wrap(row.rank, false)
	row.rank:SetPoint("RIGHT", row.fold, "LEFT", -M.rowGap, 0)

	row.name = UI.Label(row, M.font, C.text, "LEFT", UI.FLAT)
	UI.Wrap(row.name, false)
	row.name:SetPoint("LEFT", square, "RIGHT", M.gutter, 0)
	row.name:SetPoint("RIGHT", row.rank, "LEFT", -M.gutter, 0)

	rows[index] = row
	return row
end

local function Width()
	return M.pad * 2 + COLUMNS * ROW_WIDTH + (COLUMNS - 1) * BETWEEN
end

local function Height()
	return M.title + M.pad + M.tab + BETWEEN + deepest * PITCH + M.pad + M.footer
end

-- Rows per column for a tab with this many spells.
local function PerColumn(count)
	return math.max(1, math.ceil(count / COLUMNS))
end

-- Whether the tab strip changing tab is the paint below, in which case the
-- strip's own callback must not paint again.
local quiet = false

local function Select(index)
	if quiet then
		return false
	end
	UI.CloseDropdown()
	viewing = index
	return Window.Paint()
end

function Window.Build()
	if window then
		return window
	end

	window = UI.Window({
		name = "WarriorKitSpellbook",
		title = "Spell book",
		width = Width(),
		height = Height(),
		zoom = function() return ns.Zoom("spellbookZoom") end,
		-- The grid moving in the middle of a fight is a window that keeps the
		-- zoom it had until the fight ends: scaling the frame the secure
		-- squares hang off is refused, and Fit is refused for the same reason.
		rescale = function(apply)
			if InCombatLockdown() then
				pending = true
				return
			end
			apply()
			Window.Fit()
			Window.Refresh()
		end,
		-- The squares are secure buttons, so everything the client refuses an
		-- addon in combat it refuses this window: the close box runs a snippet
		-- instead of Lua, and the window is not dragged in a fight.
		secure = true,
	})
	ns.Remember(window)

	tabs = UI.TabStrip(window.content, { onSelect = Select })
	tabs.frame:SetPoint("TOPLEFT", M.pad, -M.pad)

	grid = CreateFrame("Frame", nil, window.content)
	grid:SetPoint("TOPLEFT", tabs.frame, "BOTTOMLEFT", 0, -BETWEEN)

	foot = UI.Label(window.footer, M.small, C.dim, "LEFT", UI.FLAT)
	UI.Wrap(foot, false)
	foot:SetPoint("LEFT")
	foot:SetPoint("RIGHT")

	-- Painted whenever the window comes up, by whatever route. In a fight the
	-- route is the snippet on the key, which runs no Lua of ours at all, so
	-- this is the only place a paint can be hung and still happen.
	window.frame:SetScript("OnShow", function()
		Window.Paint()
	end)

	-- Sized for an empty book, which is what it is until somebody opens it. The
	-- read below is what gives the window its real height, and it happens on the
	-- first paint.
	Window.Fit()
	return window
end

-- The book, read if something has happened to it since the last read.
--
-- Every paint goes through here and nothing else does, which is what keeps the
-- walk to one per change rather than one per event. The fit comes with it
-- because the window is sized to the tallest tab and a new rank can move that.
local function Freshen()
	if not window or not stale then
		return false
	end
	stale = false
	Window.Read()
	Window.Fit()
	return true
end

--------------------------------------------------------------------------
-- Reading and painting
--------------------------------------------------------------------------

-- The book, read again, and the strip made to match it. A tab the strip
-- already has keeps its button; one it does not is added; the count on this
-- client never goes down, so nothing is ever taken away.
function Window.Read()
	book = Read.Tabs()
	deepest = 1
	for index = 1, #book do
		local per = PerColumn(#book[index].spells)
		if per > deepest then
			deepest = per
		end
		if index > #tabs.buttons then
			tabs:Add(book[index].name)
		else
			tabs:SetLabel(index, book[index].name)
		end
	end
	if viewing > #book then
		viewing = math.max(1, #book)
	end
	return #book
end

-- Sized to the tallest tab. Refused in a fight, and put right when it drops:
-- sizing the grid sizes the frame every secure square hangs off, which is the
-- same protected act as showing it.
function Window.Fit()
	if not window then
		return false
	end
	if InCombatLockdown() then
		pending = true
		return false
	end
	local width, height = Width(), Height()
	window:Resize(width, height)
	tabs:Resize(width - M.pad * 2)
	grid:SetSize(width - M.pad * 2, deepest * PITCH)
	return true
end

-- The rows of the tab that is up, laid down the columns. Every row is
-- pictured whether or not the fight lets its square be armed, because the
-- picture is ordinary Lua and the square is not.
function Window.Paint()
	if not window then
		return false
	end
	-- The one place the book is read. Everything that draws a row comes through
	-- here, so a book read on the way to the screen is read once however many
	-- things changed it while the window was shut.
	Freshen()
	local tab = book[viewing]
	local count = tab and #tab.spells or 0
	local per = PerColumn(count)

	for index = 1, count do
		local row = Row(index)
		local spell = tab.spells[index]
		row.spell = spell
		row.pick = Chosen(spell)
		local column = math.floor((index - 1) / per)
		local down = (index - 1) % per
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", grid, "TOPLEFT", column * (ROW_WIDTH + BETWEEN), -(down * PITCH))
		PaintRow(row)
		Arm(row)
		row:Show()
	end
	for index = count + 1, #rows do
		rows[index].spell = nil
		rows[index]:Hide()
		Arm(rows[index])
	end

	if #book > 0 and tabs.selected ~= viewing then
		quiet = true
		tabs:Select(viewing)
		quiet = false
	end

	Window.Foot()
	return true
end

-- How many spells the book holds and how many squares are set below the best
-- rank you know, for the foot and the panel.
function Window.Counts()
	-- The panel's own reading asks this while the window is shut, and it is the
	-- one caller that is not a paint. It reads the book rather than answering
	-- off an empty one, because a line saying you know no spells is worse than
	-- the walk it saved.
	Freshen()
	local spells, lowered = 0, 0
	for index = 1, #book do
		for at = 1, #book[index].spells do
			local spell = book[index].spells[at]
			spells = spells + 1
			if Chosen(spell) < #spell.ranks then
				lowered = lowered + 1
			end
		end
	end
	return spells, lowered
end

function Window.Ranks()
	local spells, lowered = Window.Counts()
	if spells == 0 then
		return "no spells read off the book yet"
	end
	if lowered == 0 then
		return ("%d spells, every square at the best rank you know"):format(spells)
	end
	if lowered == 1 then
		return ("%d spells, 1 square set to a lower rank"):format(spells)
	end
	return ("%d spells, %d squares set to a lower rank"):format(spells, lowered)
end

function Window.Foot()
	if not foot then
		return false
	end
	local line = Window.Ranks()
	if pending then
		line = line .. ". The fight is holding a change back"
	end
	foot:SetText(line .. ".")
	return true
end

--------------------------------------------------------------------------
-- The key
--
-- Blizzard's own book opens in a fight and so must this one. What stops it is
-- the squares: a frame built from a secure template is protected, showing a
-- window that has a protected frame inside it is itself protected, and an
-- addon may not do a protected thing in combat. A snippet may, and a snippet
-- is the sanctioned way an addon borrows the permission.
--
-- So the key does not call any of the Lua below. It is bound to this button,
-- the button carries the snippet, and the snippet shows or hides the window.
-- Spellbook/Blizzard.lua binds the key to it, because that file already owns
-- which key opens this window and hands the key back when the switch is off.
--------------------------------------------------------------------------

local KEY = "WarriorKitSpellbookKey"

function Window.Key()
	if key then
		return key
	end
	if not Window.Build() then
		return nil
	end
	key = CreateFrame("Button", KEY, UIParent, "SecureHandlerClickTemplate")
	-- The down edge, which is the one a key bound with SetOverrideBindingClick
	-- is dispatched on with no useOnKeyDown attribute set. Registering both
	-- edges would run the snippet twice and the window would open and shut in
	-- one press.
	key:RegisterForClicks("AnyDown")
	key:SetFrameRef("window", window.frame)
	key:SetAttribute("_onclick", [[
		local book = self:GetFrameRef("window")
		if book:IsShown() then
			book:Hide()
		else
			book:Show()
		end
	]])
	return key
end

function Window.KeyName()
	return KEY
end

--------------------------------------------------------------------------

function Window.Built()
	return window ~= nil
end

function Window.Shown()
	return window ~= nil and window:IsShown()
end

-- In a fight this cannot open the window and says so. The key can.
function Window.Show()
	Window.Build()
	if InCombatLockdown() and not window:IsShown() then
		ns.Print(("the spell book opens on %s in a fight."):format(ns.BookBlizzard.KeyText()))
		return false
	end
	-- Asked before it is called, because in a fight a window that is already
	-- up is a window this may not call Show on either.
	if not window:IsShown() then
		window:Show()
	else
		Window.Paint()
	end
	return true
end

-- Refused in a fight for the reason Show is, and it names the two ways out
-- that do work, both of which are snippets: the key and the cross.
function Window.Hide()
	if not window then
		return false
	end
	if InCombatLockdown() and window:IsShown() then
		ns.Print(("the spell book closes on %s or on its own cross in a fight.")
			:format(ns.BookBlizzard.KeyText()))
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

-- Another tab, for the harness and the slash word. A tab the book does not
-- have is refused rather than drawn empty.
function Window.View(index)
	Freshen()
	if index < 1 or index > #book then
		return false
	end
	viewing = index
	return Window.Paint()
end

function Window.Viewing()
	return viewing
end

function Window.Row(index)
	return rows[index]
end

function Window.Book()
	return book
end

-- Marked either way, read only while it is up.
--
-- Reading the book is four client calls per entry over every rank you know, and
-- this runs on SPELLS_CHANGED, which the client fires at login, at a trainer, on
-- a talent change and on a handful of things that are none of those. It read and
-- refitted the window on every one of them for a window most sessions never
-- open. The mark is what the next paint pays for, and the fit rides along with
-- the read because both answer to the same change.
function Window.Refresh()
	if not window then
		return false
	end
	stale = true
	if Window.Shown() then
		return Window.Paint()
	end
	return false
end

function Window.Describe()
	if not ns.db.spellbook then
		return "off"
	end
	if not window then
		return "not built yet"
	end
	if not Window.Shown() then
		return "closed"
	end
	local tab = book[viewing]
	return ("open on %s"):format(tab and tab.name or "nothing")
end

--------------------------------------------------------------------------
-- Events
--
-- LEARNED_SPELL_IN_TAB is pcalled on, because the 2.5.6 client does not
-- carry it and registering an event a client has never heard of raises.
-- SPELLS_CHANGED covers the trainer on a client without it.
--------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("SPELLS_CHANGED")
events:RegisterEvent("PLAYER_LEVEL_UP")
pcall(events.RegisterEvent, events, "LEARNED_SPELL_IN_TAB")
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		if ns.db.spellbook then
			Window.Build()
		end
		return
	end
	if event == "PLAYER_REGEN_ENABLED" then
		-- Whatever the fight refused, in one pass: the fit, then every square
		-- armed again by the paint.
		if pending then
			pending = false
			Window.Fit()
			if window then
				Window.Paint()
			end
		end
		return
	end
	Window.Refresh()
end)
