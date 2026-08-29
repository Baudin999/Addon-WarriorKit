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
-- The gesture the page is built around is two moves and no dialog. Drag a spell
-- onto the square, press the key you want it on. That is what Clique's editor
-- does and it is the one part of Clique nobody has ever needed the manual for,
-- so it is copied on purpose.
--------------------------------------------------------------------------

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

-- The icon and the line beside it. A slot with nothing in it says what to do
-- with it, because an empty square with no caption is a square nobody drops
-- anything on.
local function Slotted()
	local pick = ns.Hover.Held()
	if not pick then
		return nil, "|cff808080drag a spell here|r"
	end
	return pick.icon, pick.name
end

-- One row of the list: the key, the spell's icon and name, who it lands on, and
-- the button that takes it off.
--
-- ui.Custom is the seam, the same as UnitFrames/Panel.lua's debuff rows.
-- UI/Widgets.lua has no list widget and should not grow one for two callers;
-- what it has is a bare row of the right width that measures itself, and an
-- unused slot measures to nothing.
local function BindRow(ui, index)
	local M, C = ns.UI.Metric, ns.UI.Color
	local removeWidth, keyWidth = 62, 128
	local row, art, key, name

	local function Bind()
		return ns.Hover.List()[index]
	end

	ui.Custom(function(frame)
		row = frame

		key = ns.UI.Label(frame, M.font, C.text, "LEFT", ns.UI.FLAT)
		key:SetPoint("TOPLEFT")
		key:SetWidth(keyWidth)

		art = ns.UI.Icon(frame, "ARTWORK")
		art:SetSize(M.control, M.control)
		art:SetPoint("TOPLEFT", frame, "TOPLEFT", keyWidth + M.gutter, 0)

		local remove = ns.UI.Button(frame, { label = "remove", width = removeWidth,
			onClick = function()
				if ns.Hover.Remove(index) then
					ns.Options.Refresh()
				end
			end })
		remove:SetPoint("TOPRIGHT")

		name = ns.UI.Label(frame, M.font, C.text, "LEFT", ns.UI.FLAT)
		name:SetPoint("LEFT", art, "RIGHT", M.gutter, 0)
		name:SetPoint("RIGHT", remove, "LEFT", -M.gutter, 0)

		-- An unbound slot is not a short row, it is no row: zero height and no
		-- gap under it, or twelve unused slots would leave a hand's width of air
		-- between the list and the controls below it.
		return function(cell)
			local used = Bind() ~= nil
			cell.gap = used and M.rowGap or 0
			return used and M.control or 0
		end
	end, { height = M.control, refresh = function()
		local bind = Bind()
		row:SetShown(bind ~= nil)
		if not bind then
			return
		end
		art:SetTexture(bind.icon)
		name:SetText(("%s, on %s"):format(bind.name, ns.Hover.Who(bind.who).label))
		-- A key the client refused is drawn in the quiet grey rather than left
		-- looking bound, because a key that reads as live and casts nothing is
		-- the one failure this page cannot otherwise show.
		local tone = ns.HoverCast.Holding(index) and C.text or C.quiet
		key:SetText(bind.key)
		key:SetTextColor(tone[1], tone[2], tone[3])
	end })
end

local function Who()
	local options = {}
	for _, who in ipairs(ns.Hover.WHO) do
		options[#options + 1] = { value = who.id, text = who.label }
	end
	return options
end

local function Binding(ui)
	ui.Section("Mouseover casting", "Fighting")
	ui.Lede("A key casts on whatever is under the cursor, filtered by whether it is a friend or an enemy.")

	ui.Slot("the spell", Slotted, function(pick)
		ns.Hover.Hold(pick)
		return true
	end, { take = Take })
	ui.Hint("Drag a spell out of your spellbook or off a bar. Right click the square to empty it. An item works too, and is cast with /use.")

	ui.Picker("cast it on", function() return ns.db.hoverWho end,
		function(value) ns.db.hoverWho = value end, Who)
	ui.Hint("An enemy is anything you can attack, a friend is anything you can help. Neither ever fires on the other, so one key can carry both.")

	ui.KeyField("bind it to",
		function()
			return ns.Hover.Held() and "|cffffd100press a key|r" or "|cff808080fill the slot first|r"
		end,
		function(combo)
			local ok, why = ns.Hover.Bind(combo)
			if not ok then
				ns.Print(why)
			end
		end,
		function() ns.Hover.Hold(nil) end)
	ui.Hint("Click the field and press what you want, mouse buttons included. Plain left and right click are refused: they belong to targeting and to the camera.")

	ui.Check("fall back to your target",
		function() return ns.db.hoverFallback end,
		function(value)
			ns.db.hoverFallback = value
			ns.Hover.Changed()
		end)
	ui.Hint("Off, a key with nothing under the cursor does nothing. On, it casts on your target instead, and only when your target passes the same filter.")
end

local function Bound(ui)
	ui.Section("What is bound", "Fighting")
	ui.Lede("Every key this part holds, in the order you made them.")

	for index = 1, ns.Hover.MAX do
		BindRow(ui, index)
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
	Bound(ui)
	OnScreen(ui)
end
