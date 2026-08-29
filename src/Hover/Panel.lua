local ADDON, ns = ...

local Panel = {}
ns.HoverPanel = Panel

--------------------------------------------------------------------------
-- The part's page in the options window, and nothing else.
--
-- Its own file for the reason UnitFrames/Panel.lua is one: everything here
-- reads a setting, draws a control and writes it back, and nothing here decides
-- anything. What is left in Feature.lua is the part's contract with Core.
--
-- The page is a list of rows and one empty row at the top of it. A row is a
-- whole binding: the spell, the key, who it lands on, and the cross that takes
-- it off. Fill the empty row and it becomes a bound one and a new empty row is
-- under your cursor again.
--
-- It was three stacked controls and a read-only list underneath, which is the
-- shape a settings page falls into when each control is added on its own. It
-- asked for the three decisions in a fixed order, in three different places on
-- the page, and once a binding was made the only thing you could do to it was
-- delete it and start again. Every one of those is the same defect: the thing
-- being edited is a row and the page was not drawing rows.
--
-- So the row is the widget and the empty one is the same widget with a draft
-- behind it rather than a saved binding. Nothing on the page has an order you
-- have to follow, changing your mind about any one column costs one click, and
-- what is bound is where you would reach for it, which is on the binding.
--------------------------------------------------------------------------

local M, C = ns.UI.Metric, ns.UI.Color

-- The row's own geometry, and the only numbers in this file. The key box is
-- sized for CTRL-SHIFT-BUTTON4 and the target button for "an enemy"; the name
-- takes whatever is left, because it is the one column that can be trimmed with
-- an ellipsis and still say which spell it is.
local SQUARE, KEY_W, WHO_W = M.control, 118, 76

-- What the slot will take off the cursor, handed to the widget layer, which
-- knows what a square is and nothing about a spell.
--
-- A refusal is said once per reason rather than once per ask. The widget puts
-- the same question to this on the way in as it does on a drop, so a cursor
-- carrying something the slot will not take passes through here every time the
-- mouse crosses the square, and a line per pass fills the chat frame with one
-- sentence. Keyed by the sentence itself, the way Buttons/Square.lua keys its
-- own, so a second thing going wrong still gets said.
local told = {}

local function Take(kind, a, b, c)
	local pick, why = ns.Hover.Carry(kind, a, b, c)
	if pick then
		return pick
	end
	if why and not told[why] then
		told[why] = true
		ns.Print(why)
	end
	return nil
end

-- Every writer on this page answers the same way Hover.Bind does, so the page
-- says the refusal and puts itself back in step in one place.
local function Said(ok, why)
	if not ok and why then
		ns.Print(why)
	end
	ns.Options.Refresh()
	return ok
end

--------------------------------------------------------------------------
-- One row
--
-- Five regions and no decisions. What each column reads and what it writes
-- comes in as `hooks`, which is the whole of the difference between the empty
-- row at the top and the twelve bound ones under it.
--
-- ui.Custom is the seam, the same as UnitFrames/Panel.lua's debuff rows.
-- UI/Widgets.lua has the square and the key box as callable pieces and no list
-- widget over them, which is the right split: a list is a thing a page has an
-- opinion about and a square is not.
--------------------------------------------------------------------------

local function Row(ui, hooks)
	local row, square, name, key, who

	ui.Custom(function(frame)
		row = frame

		square = ns.UI.DropSquare(frame, SQUARE, hooks.slot, hooks.drop,
			{ take = Take, after = ns.Options.Refresh })
		square:SetPoint("TOPLEFT")

		-- The cross column is left empty on the row that has nothing to take
		-- off, rather than closed up. Every row on this page is the same four
		-- columns and the empty one at the top has to line up with them, or the
		-- eye reads it as a different kind of thing than the rows it makes.
		if hooks.remove then
			local cross = ns.UI.Button(frame, { label = "x", glyph = true,
				width = SQUARE, onClick = hooks.remove })
			cross:SetPoint("TOPRIGHT")
		end

		who = ns.UI.Button(frame, { width = WHO_W, onClick = hooks.cycle })
		who:SetPoint("TOPRIGHT", -(SQUARE + M.rowGap), 0)

		key = ns.UI.KeyBox(frame, { width = KEY_W, getText = hooks.key,
			onKey = hooks.bind, after = ns.Options.Refresh })
		key:SetPoint("TOPRIGHT", who, "TOPLEFT", -M.rowGap, 0)

		name = ns.UI.Label(frame, M.font, C.text, "LEFT", ns.UI.FLAT)
		ns.UI.Wrap(name, false)
		name:SetPoint("LEFT", square, "RIGHT", M.gutter, 0)
		name:SetPoint("RIGHT", key, "LEFT", -M.gutter, 0)

		-- An empty slot on the list is not a short row, it is no row: zero
		-- height and no gap under it, or twelve unused slots would leave a
		-- hand's width of air between the list and the controls below it.
		return function(cell)
			local used = hooks.shown()
			cell.gap = used and M.rowGap or 0
			return used and SQUARE or 0
		end
	end, { height = SQUARE, label = hooks.label, refresh = function()
		local used = hooks.shown()
		row:SetShown(used)
		if not used then
			return
		end
		name:SetText(square.Refresh() or "")
		who.text:SetText(ns.Hover.Who(hooks.who()).label)
		key.Update()
	end })
end

--------------------------------------------------------------------------
-- The empty row, and the twelve under it
--------------------------------------------------------------------------

-- The draft. The slot holds what you dropped and ns.db.hoverWho holds the
-- filter the next binding is made with, which is what the page had before and
-- is exactly a row that has not been saved. Pressing a key is what saves it.
local function Draft()
	return {
		label = "a new key",
		shown = function() return true end,
		slot = function()
			local pick = ns.Hover.Held()
			if not pick then
				return nil, "|cff808080drag a spell here|r"
			end
			return pick.icon, pick.name
		end,
		drop = function(pick)
			ns.Hover.Hold(pick)
			return true
		end,
		key = function()
			return ns.Hover.Held() and "|cffffd100press a key|r" or "|cff808080a key|r"
		end,
		bind = function(combo)
			Said(ns.Hover.Bind(combo))
		end,
		who = function() return ns.db.hoverWho end,
		cycle = function()
			ns.db.hoverWho = ns.Hover.NextWho(ns.db.hoverWho)
			ns.Options.Refresh()
		end,
	}
end

-- One saved binding. Every column writes straight through to the model, so a
-- row is the binding rather than a picture of it.
local function Saved(index)
	local function Bind()
		return ns.Hover.List()[index]
	end
	return {
		shown = function() return Bind() ~= nil end,
		slot = function()
			local bind = Bind()
			return bind and bind.icon, bind and bind.name
		end,
		drop = function(pick)
			return Said(ns.Hover.Respell(index, pick))
		end,
		-- A key the client refused is drawn in the quiet grey rather than left
		-- looking bound, because a key that reads as live and casts nothing is
		-- the one failure this page cannot otherwise show.
		key = function()
			local bind = Bind()
			if not bind then
				return ""
			end
			if ns.HoverCast.Holding(index) then
				return bind.key
			end
			return ("|cff808080%s|r"):format(bind.key)
		end,
		bind = function(combo)
			Said(ns.Hover.Rebind(index, combo))
		end,
		who = function()
			local bind = Bind()
			return bind and bind.who
		end,
		cycle = function()
			local bind = Bind()
			if bind then
				Said(ns.Hover.Retarget(index, ns.Hover.NextWho(bind.who)))
			end
		end,
		remove = function()
			ns.Hover.Remove(index)
			ns.Options.Refresh()
		end,
	}
end

local function Binding(ui)
	ui.Section("Mouseover casting", "Fighting")
	ui.Lede("A key casts on whatever is under the cursor, filtered by whether it is a friend or an enemy.")

	Row(ui, Draft())
	ui.Hint("Drag a spell onto the square, press the key you want it on, and click the button to say who it lands on. An item works too.")

	for index = 1, ns.Hover.MAX do
		Row(ui, Saved(index))
	end

	ui.Reading("the keys", function()
		return ns.Hover.Describe()
	end)

	ui.Action(function() return "clear every key" end, function()
		ns.Hover.Clear()
		ns.Options.Refresh()
	end, function() return #ns.Hover.List() > 0 end)
end

local function OnScreen(ui)
	ui.Section("The list on screen", "Fighting")
	ui.Lede("The same list drawn over the world, so what you bound is something you can see rather than remember.")

	ui.Check("show it",
		function() return ns.db.hoverSheet end,
		function(value)
			ns.db.hoverSheet = value
			ns.HoverSheet.Rebuild()
		end)
	ui.Hint("It is only up while something is bound. Red is an enemy key, green is a friend key, grey lands on either.")

	ui.Opacity("background",
		function() return ns.db.hoverSheetAlpha end,
		function(value)
			ns.db.hoverSheetAlpha = value
			ns.HoverSheet.Rebuild()
		end)

	ui.Zoom(function() return ns.db.hoverSheetZoom end,
		function(value)
			ns.db.hoverSheetZoom = value
			ns.HoverSheet.Apply()
		end)

	ui.Action(function() return "put the list back" end, function()
		ns.HoverSheet.Reset()
	end)
end

function Panel.Build(ui)
	Binding(ui)
	OnScreen(ui)
end
