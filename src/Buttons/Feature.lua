local ADDON, ns = ...

-- Everything Core and the panel need to know about the loadout. Layout.lua
-- holds the behaviour and never talks to either.

local function Report(report)
	ns.Print(("filled %d slots."):format(report.placed))
	if #report.skipped > 0 then
		local seen, list = {}, {}
		for _, name in ipairs(report.skipped) do
			if not seen[name] then
				seen[name] = true
				list[#list + 1] = name
			end
		end
		ns.Print("not yet learned, left empty: " .. table.concat(list, ", ") .. ".")
	end
	if report.macroFail then
		ns.Print(("%d macros could not be created."):format(report.macroFail))
	end
	if report.note then
		ns.Print(report.note .. ".")
	end
	ns.Print("your old bars are saved. /reload now to make that backup survive a crash.")
end

local function Apply()
	local ok, result = ns.Layout.Apply()
	if not ok then
		ns.Print("cannot fill the bars: " .. result .. ".")
		return
	end
	Report(result)
	ns.Options.Refresh()
end

local function RefreshRanks()
	local ok, result = ns.Ranks.Apply()
	if not ok then
		ns.Print("cannot refresh spell ranks: " .. result .. ".")
		return
	end
	if result.moved == 0 then
		ns.Print("every spell on your bars is already the best rank you know.")
	else
		ns.Print(("moved %d slot%s up to your best rank."):format(
			result.moved, result.moved == 1 and "" or "s"))
	end
	if #result.failed > 0 then
		ns.Print("could not place: " .. table.concat(result.failed, ", ") .. ".")
	end
	ns.Options.Refresh()
end

-- The clone, which is the other half of this part: Layout writes the slots and
-- Bars draws them. One feature rather than two, because they are one job seen
-- from two ends and a panel that split them would ask the same question twice.
local function SetBars(value)
	ns.db.actionBars = value and true or false
	local complete = ns.Bars.Apply()
	ns.Print("action bars " .. (ns.db.actionBars and "cloned" or "handed back")
		.. ": " .. ns.Bars.Describe() .. ".")
	if not complete then
		ns.Print("part of that needs combat to end first, and will run then.")
	end
	ns.Options.Refresh()
end

-- One bar, ticked or unticked. Which.lua holds the decision and Bars.Apply is
-- what makes the screen agree with it, the same shape SetBars has.
local function SetBar(def, value)
	ns.WhichBars.Want(def.key, value)
	local complete = ns.Bars.Apply()
	ns.Print(def.label .. (value and " cloned." or " handed back."))
	if not complete then
		ns.Print("part of that needs combat to end first, and will run then.")
	end
	ns.Options.Refresh()
end

-- One bar's shape, colour or hours changed, and the screen made to agree.
--
-- Every control on the page below ends here, because all six of them are one
-- job: write the record in Buttons/Look.lua and lay the standing bars out
-- again. Restyle refuses in combat and says so, the same as everything else in
-- this part that touches a secure frame.
local function Restyle()
	if not ns.Bars.Restyle() then
		ns.Print("part of that needs combat to end first, and will run then.")
	end
	ns.Options.Refresh()
end

-- Which bar the page is showing. The tab strip picks it and every control on
-- the page reads it, so a control is written once rather than five times.
local function Chosen()
	return ns.BarLook.Chosen()
end

-- Every per-bar look dropped, so all five are the plan again. The counterpart
-- of Match on the rows above, and a deletion for the same reason: the shipping
-- state has no records in it.
local function Plain()
	local dropped = ns.BarLook.Plain()
	if dropped == 0 then
		ns.Print("every bar is already the plain shape the plan draws.")
	else
		ns.Print(("dropped the look on %d bar%s, back to the plain shape."):format(
			dropped, dropped == 1 and "" or "s"))
	end
	Restyle()
end

-- One axis of one bar put on the middle of the screen. The other axis is left
-- exactly where it was, which is the whole of what the two buttons are for.
local function Centre(axis)
	local def = Chosen()
	local ok, why = ns.Bars.Centre(def, axis)
	if not ok then
		ns.Print(why == "combat" and "that has to wait until combat ends."
			or (def.label .. " is not up, so there is nothing to centre."))
		return
	end
	ns.Print(def.label .. " centred " .. (axis == "x" and "left to right." or "up and down."))
	ns.Options.Refresh()
end

-- Back to cloning whatever you have on, which is the shipping state and is what
-- makes this feature quick to start with: no list to tick, no bar to place, the
-- bars you already had with the keys you already set.
local function Match()
	local dropped = ns.WhichBars.Follow()
	ns.Bars.Apply()
	if dropped == 0 then
		ns.Print("already following your own bars: " .. ns.Bars.Describe() .. ".")
	else
		ns.Print(("dropped %d bar choice%s, following your own bars again: %s."):format(
			dropped, dropped == 1 and "" or "s", ns.Bars.Describe()))
	end
	ns.Options.Refresh()
end

local function Restore()
	local ok, result = ns.Layout.Restore()
	if not ok then
		ns.Print("cannot put your bars back: " .. result .. ".")
		return
	end
	ns.Print(("put back %d slots%s."):format(result.restored,
		result.failed > 0 and (", %d could not be placed"):format(result.failed) or ""))
	ns.Options.Refresh()
end

-- What the millisecond figure on the performance tab is per. 0.4 ms means one
-- thing at twelve squares and another at sixty. Registered from here rather
-- than from Bars.lua, because a behaviour file names nothing outside its folder.
if ns.Perf then
	ns.Perf.Gauge("bar squares on screen", function()
		return ns.Bars.Count()
	end)
end

-- Printed rather than written, because an addon cannot write its own source
-- and the plan in Buttons/Bars.lua is where a position belongs if it is to
-- survive a fresh clone. Drag it, print it, paste it, reset it.
local function Where()
	local lines = ns.Bars.Where()
	if #lines == 0 then
		ns.Print("no bars are up, so there is nothing to place. actionbars on first.")
		return
	end
	ns.Print("where the bars are, in the shape the plan in Buttons/Bars.lua wants:")
	for _, line in ipairs(lines) do
		ns.Print(line)
	end
	ns.Print("paste those over the geometry in that file, then actionbars reset.")
end

-- The trace, on or off. A toggle rather than on and off words, because it is
-- one switch pressed twice in the same minute by somebody with a question, and
-- because it is deliberately not saved: nothing here survives a reload.
local function Trace()
	local on = ns.BarTrace.Set(not ns.BarTrace.Running())
	ns.Print("square trace " .. ns.BarTrace.Describe() .. ".")
	if on then
		ns.Print("drag a spell over the bar that will not take it, then actionbars trace again to stop.")
	end
end

-- The page for one bar at a time
--
-- Five bars times six controls is thirty rows, and thirty rows is a page you
-- search rather than read. So the strip picks a bar and one set of controls
-- answers for whichever is in front, which is the shape the loadouts page and
-- the people page already have.
--
-- Its own function rather than forty more lines inside `panel`, along the seam
-- the file already has: everything in here is about one bar and nothing in here
-- is about the loadout, the clone as a whole or the spell ranks.
local function EachBarPage(ui)
	ui.Section("Each bar", "Fighting")
	ui.Lede("What one bar looks like: how the twelve fold, what they stand on, and when it is on the screen.")

	ui.Tabs(
		function()
			local labels = {}
			for index, def in ipairs(ns.WhichBars.PLAN) do
				labels[index] = def.tab
			end
			return labels
		end,
		ns.BarLook.Shown,
		function(index)
			ns.BarLook.Show(index)
			-- The rim moves with the strip, which is the whole point of it.
			ns.Bars.ApplyMark()
		end)

	ui.Check("clone this bar",
		function() return ns.WhichBars.Wanted(Chosen()) end,
		function(value) SetBar(Chosen(), value) end)

	ui.Count("rows", ns.BarLook.ROWS[1], ns.BarLook.ROWS[#ns.BarLook.ROWS],
		function() return ns.BarLook.Rows(Chosen()) end,
		function(value)
			ns.BarLook.StepRows(Chosen(), value)
			Restyle()
		end)
	ui.Hint("Twelve buttons, so the shapes are 1, 2, 3, 4, 6 and 12 rows and the stepper walks between them.")

	local sizeLow, sizeHigh = ns.BarLook.SizeRange()
	ui.Slider("square", sizeLow, sizeHigh, 1,
		function() return ns.BarLook.Size(Chosen()) end,
		function(value)
			ns.BarLook.SetSize(Chosen(), value)
			Restyle()
		end,
		function(value) return value .. "px" end)
	ui.Hint("27 and 54 are the two sizes a stored icon lands on a pixel at. In between, the client blends two copies and the art softens.")

	ui.Picker("colour",
		function() return ns.BarLook.Color(Chosen()) end,
		function(value)
			ns.BarLook.SetColor(Chosen(), value)
			Restyle()
		end,
		function()
			local options = {}
			for index, entry in ipairs(ns.BarLook.PALETTE) do
				options[index] = { value = entry.key, text = entry.label }
			end
			return options
		end)

	ui.Opacity("background",
		function() return ns.BarLook.Alpha(Chosen()) end,
		function(value)
			ns.BarLook.SetAlpha(Chosen(), value)
			Restyle()
		end)
	ui.Hint("How much of that colour you see. At nothing the hairline goes with it and the squares stand on the world.")

	ui.Check("down in combat",
		function() return ns.BarLook.Combat(Chosen()) end,
		function(value)
			ns.BarLook.SetCombat(Chosen(), value)
			Restyle()
		end)
	ui.Hint("The client hides it for us, because a bar full of secure buttons cannot be hidden from Lua once a fight has started. Its keys go on working while it is down.")

	ui.Picker("up while holding",
		function() return ns.BarLook.Key(Chosen()) end,
		function(value)
			ns.BarLook.SetKey(Chosen(), value)
			Restyle()
		end,
		function()
			local options = {}
			for index, entry in ipairs(ns.BarLook.KEYS) do
				options[index] = { value = entry.key, text = entry.label }
			end
			return options
		end)
	ui.Hint("A key hides the bar until you hold it, in a fight or out of one, so a bar waiting on one leaves the switch above nothing to decide.")

	ui.ActionPair(
		function() return "centre left to right" end,
		function() Centre("x") end,
		function() return ns.Bars.Standing(Chosen()) end,
		function() return "centre up and down" end,
		function() Centre("y") end,
		function() return ns.Bars.Standing(Chosen()) end)

	ui.Check("lock the bars",
		function() return ns.db.barsLocked end,
		function(value)
			ns.db.barsLocked = value and true or false
			ns.Bars.ApplyLock()
			ns.Print("bars " .. (ns.db.barsLocked and "locked."
				or "loose: hold shift and drag one."))
			ns.Options.Refresh()
		end)
	ui.Hint("Locked, a bar moves only while /wk unlock has every frame loose. Unlocked, hold shift to drag one, and a shift-click over a bar belongs to the bar while you hold it.")

	ui.Action(
		function() return "back to the plain bars" end,
		Plain,
		function() return ns.BarLook.Decided() > 0 end)

	ui.Reading("this bar", function() return ns.BarLook.Shape(Chosen()) end)
	ui.Reading("on screen", function() return ns.BarLook.Hours(Chosen()) end)
end

-- The words that set one bar's look
--
-- Five settings, each `actionbars <word> <bar> <value>`, split out of the
-- dispatcher below because they share every line of their parsing: which bar,
-- then what to do to it. The bar is named by the plan's key or by the label the
-- tab strip carries, so both `bottomleft` and "bottom left" arrive here.
--
-- Returns false for a word this does not own, so the caller can go on to its
-- own list rather than this one having to know it.
-- The words this owns, as a lookup rather than a chain of comparisons, so
-- adding the next one is a line and not a branch.
local LOOK_WORDS = {
	rows = true, square = true, colour = true, background = true,
	combat = true, key = true, centre = true,
}

-- The odd one out, in a function of its own: every other word writes a setting
-- and this one moves a bar, and it is the only one whose value is not a number
-- or a name out of a table.
local function CentreWord(def, value)
	local axis = (value == "across" and "x") or (value == "down" and "y")
	if not axis then
		ns.Print("centre takes across or down.")
		return
	end
	local moved, why = ns.Bars.Centre(def, axis)
	if moved then
		ns.Print(def.label .. " centred.")
	elseif why == "combat" then
		ns.Print("that has to wait until combat ends.")
	else
		ns.Print(def.label .. " is not up, so there is nothing to centre.")
	end
end

local function LookWord(word, rest)
	local ROWS = ns.BarLook.ROWS
	if not LOOK_WORDS[word] then
		return false
	end

	local name, value = rest:match("^(%S*)%s*(.-)%s*$")
	local def = ns.BarLook.Find(name)
	if not def then
		ns.Print("name a bar: bar1, bottomleft, bottomright, right or right2.")
		return true
	end

	local ok = false
	if word == "rows" then
		local rows = ns.Command.Number(value, ROWS[1], ROWS[#ROWS], "rows")
		ok = rows ~= nil and ns.BarLook.SetRows(def, rows)
		if rows and not ok then
			ns.Print("twelve buttons make 1, 2, 3, 4, 6 or 12 rows and nothing else.")
		end
	elseif word == "square" then
		local low, high = ns.BarLook.SizeRange()
		local size = ns.Command.Number(value, low, high, "square")
		ok = size ~= nil and ns.BarLook.SetSize(def, size)
	elseif word == "centre" then
		-- Named by the axis in words rather than as x and y, because the two
		-- buttons on the page say "left to right" and "up and down", and a
		-- command that says something else is a second name for one thing.
		CentreWord(def, value)
	elseif word == "colour" then
		ok = ns.BarLook.SetColor(def, value)
		if not ok then
			ns.Print("colour takes one of: " .. ns.BarLook.Colours() .. ".")
		end
	elseif word == "background" then
		local alpha = ns.Command.Step(value, ns.UI.ALPHA_LOW, ns.UI.ALPHA_HIGH,
			ns.UI.ALPHA_STEP, "background")
		ok = alpha ~= nil and ns.BarLook.SetAlpha(def, alpha)
	elseif word == "combat" then
		-- `actionbars combat bar1 on` reads as "combat: on", which is the bar
		-- going down when one starts. Off is the shipping answer.
		ok = ns.BarLook.SetCombat(def, ns.Command.Toggle(value))
	elseif word == "key" then
		ok = ns.BarLook.SetKey(def, value)
		if not ok then
			ns.Print("key takes one of: " .. ns.BarLook.Keys() .. ".")
		end
	end

	if ok then
		Restyle()
		ns.Print(def.label .. ": " .. ns.BarLook.Shape(def)
			.. ", " .. ns.BarLook.Hours(def) .. ".")
	end
	return true
end

-- The loadout page, which is the one page of this part that only exists on a
-- class somebody has written a plan for. Lifted out of the panel builder so the
-- gate on it reads as one line there rather than as a fold around half the
-- function.
local function LoadoutPage(ui)
	ui.Section("Buttons", ns.Options.CLASS)
	ui.Lede("Fills bar 1 with a role per key on every page it has, and the shift layer above it.")
	ui.ActionPair(
		function() return ns.Layout.HasBackup() and "re-fill the bars" or "fill the bars" end,
		Apply,
		function() return (ns.Layout.CanApply()) end,
		function() return "put mine back" end,
		Restore,
		function() return ns.Layout.HasBackup() and (ns.Layout.CanApply()) end)
	ui.Hint("Your keybindings are never touched, and nothing is overwritten until you press it. What was in the slots is kept, so the right button hands it all back.")
	ui.Reading("the bars", function()
		local can, why = ns.Layout.CanApply()
		if not can then
			return why
		end
		return ns.Layout.Describe()
	end)
	ui.Reading("your old bars", function()
		if not ns.Layout.HasBackup() then
			return "not held"
		end
		return "held from " .. ns.Layout.BackupStamp()
	end)
end

ns.Register({
	name = "buttons",
	order = 6,

	switch = {
		key = "actionBars",
		label = "our own action bars",
		apply = function(value) SetBars(value) end,
	},

	defaults = {
		-- On. It hides Blizzard's own buttons the moment you log in and puts
		-- the five bars where the plan in Buttons/Which.lua says, which is the
		-- layout this addon is for; leaving it off shipped an addon that drew
		-- everything except the part of the screen you actually press.
		-- `/wk actionbars off` gives the client's bars back without a reload.
		actionBars = true,

		-- Where a bar has been dragged to, keyed by the plan's bar key. Empty
		-- is the normal state and means the plan in Buttons/Bars.lua decides,
		-- which is the one that travels with a clone of the addon. An entry
		-- here is a position you are still trying out: `actionbars where`
		-- prints it in the plan's own shape to paste in, and `actionbars reset`
		-- drops it again once you have.
		barPoints = {},

		-- What each bar looks like and when it is up, keyed by the plan's bar
		-- key: the rows the twelve fold into, the colour and the opacity of the
		-- ground under them, whether the bar goes down in combat and which key
		-- holds it up. Empty is the normal state and means every bar is the
		-- plan's own shape in the window colour, always up. Buttons/Look.lua
		-- owns every one of those answers and the defaults behind them.
		barLook = {},

		-- Whether the cloned bars can be dragged with shift alone. Off is the
		-- shipping answer: holding shift puts a drag handle over each bar for
		-- as long as you hold it, so a bar is moved where you can see what it
		-- is next to rather than after an unlock. A shift-click on a square
		-- goes to that handle rather than to the square while it is up, which
		-- is what it costs and why it is a setting. On means they move only
		-- while every frame in the addon is unlocked, which is /wk unlock.
		barsLocked = false,

		-- Which bars are cloned, keyed by the plan's bar key. Empty is the
		-- normal state and means every bar follows your own: one you have on is
		-- one we clone, which is what makes turning this on give you back the
		-- interface you already had. An entry here is a bar you have decided
		-- about, and the client's own switch stops being consulted for it.
		barsShown = {},
	},

	-- Per character, all three of them. These describe one character's action
	-- bars and one character's macros. Held account-wide, the first character to
	-- apply the loadout would own the only backup, the second would overwrite
	-- its bars without taking one, and restoring on the second would write the
	-- first one's bars into its slots.
	charDefaults = {
		-- What was in every slot the loadout touches, taken the first time it
		-- is applied and kept until it is put back.
		layoutBackup = {},
		layoutStamp = "",
		-- Macros this feature created, so restore deletes exactly those.
		layoutMacros = {},
	},

	-- /wk unlock reaches the bars through here, the same way it reaches the
	-- charge icon and the meters. Without it the handles never show and the
	-- bars are the one part of the addon you cannot drag.
	lock = function()
		ns.Bars.ApplyLock()
	end,

	-- The options window, opened and closed. The page above marks whichever bar
	-- its tab strip is on, so the mark goes up with the window and comes off
	-- with it: an accent rim round a bar for the rest of the session, with the
	-- window that explained it shut, is worse than no mark at all.
	showing = function(open)
		ns.BarLook.Marking(open)
		ns.Bars.ApplyMark()
	end,

	words = {
		-- Not "bars": the enemy bars part claimed that word years ago and Core
		-- asserts at login that no two features share one.
		actionbars = function(arg)
			-- The two word forms first, because everything below is one word and
			-- a look word carries a bar name and a value after it.
			local head, rest = arg:match("^(%S*)%s*(.-)%s*$")
			if LookWord(head, rest) then
				return
			end
			if arg == "on" or arg == "off" then
				SetBars(ns.Command.Toggle(arg))
			elseif arg == "where" then
				Where()
			elseif arg == "match" then
				Match()
			elseif arg == "trace" then
				Trace()
			elseif arg == "plain" then
				Plain()
			elseif arg == "lock" or arg == "unlock" then
				ns.db.barsLocked = arg == "lock"
				ns.Bars.ApplyLock()
				ns.Print("bars " .. (ns.db.barsLocked and "locked."
					or "loose: hold shift and drag one."))
			elseif arg == "reset" then
				local dropped = ns.Bars.ResetPlacing()
				ns.Print(dropped == 0 and "nothing was dragged, so the plan was already what you see."
					or ("dropped %d dragged position%s, back to the plan."):format(
						dropped, dropped == 1 and "" or "s"))
			else
				ns.Print("action bars: " .. ns.Bars.Describe() .. ".")
				ns.Print("actionbars on clones every bar you have, with its keys, and hides Blizzard's. actionbars off gives them back.")
				ns.Print("tick bars one at a time in the panel, or actionbars match to follow your own again.")
				ns.Print("/wk unlock to drag them, actionbars where to print what you dragged, actionbars reset to undo it.")
				ns.Print("actionbars rows|square|colour|background|combat|key <bar> <value> shapes one bar. actionbars plain drops the lot.")
				ns.Print("actionbars centre <bar> across|down puts its middle on the middle of the screen, one axis at a time.")
				ns.Print("actionbars unlock to drag them with shift held, actionbars lock to stop that.")
				ns.Print("actionbars trace when a square will not take a drop: it prints what the mouse is really touching.")
			end
		end,

		ranks = function(arg)
			if arg == "refresh" or arg == "apply" then
				RefreshRanks()
			else
				ns.Print("ranks: " .. ns.Ranks.Describe() .. ".")
				ns.Print("ranks refresh moves every bar slot up to your best rank. Macros are left alone.")
			end
		end,

		buttons = function(arg)
			if arg == "apply" or arg == "fill" then
				Apply()
			elseif arg == "restore" or arg == "undo" then
				Restore()
			else
				ns.Print("buttons: " .. ns.Layout.Describe() .. ".")
				ns.Print(ns.Layout.HasBackup()
					and ("your old bars are backed up from " .. ns.Layout.BackupStamp() .. ".")
					or "no backup held, so applying will take one first.")
				ns.Print("buttons apply fills the bars, buttons restore puts yours back.")
			end
		end,
	},

	help = {
		"buttons apply, buttons restore, buttons status",
		"actionbars on|off, our own bars over Blizzard's, same slots and same keys",
		"actionbars match, back to cloning whichever bars you have on",
		"actionbars where, actionbars reset, after dragging them with /wk unlock",
		"actionbars rows|square|colour|background|combat|key <bar> <value>, one bar's shape, ground and hours",
		"actionbars centre <bar> across|down, its middle on the middle of the screen",
		"actionbars plain, every bar back to the plan's own shape",
		"actionbars lock|unlock, whether shift and a drag moves a bar",
		"actionbars trace, what the mouse is really touching, for a square that will not take a drop",
		"ranks, ranks refresh",
	},

	status = function()
		local ranks = ("%d slots holding an older rank"):format(#ns.Ranks.Stale())
		local bars = "bars " .. ns.Bars.Describe()
		-- The reaction windows are here because the only way to check their
		-- length against the live client is to read the seconds off a status
		-- line while something is dodging you. Nothing else in the addon can
		-- show you a number this file guessed.
		local windows = "reactions " .. ns.Reaction.Describe()
			.. " | conditions " .. ns.Requires.Describe()
		if not ns.Layout.HasBackup() then
			return "not applied, " .. ns.Layout.Describe()
				.. " | " .. ranks .. " | " .. bars .. " | " .. windows
		end
		return "applied, backup from " .. ns.Layout.BackupStamp()
			.. " | " .. ranks .. " | " .. bars .. " | " .. windows
	end,

	-- No reset hook. /wk reset puts frames back where they started, and where
	-- the cloned bars sit is not a setting to start from: it is a table in
	-- Bars.lua. Turning the clone off is a decision, not a reset, so it stays on
	-- the switch that says so.

	panel = function(ui)
		-- The loadout is the one page of this part that belongs to a class, so it
		-- sits under the rail entry named after you and is not built at all where
		-- nobody has written a plan. The two pages under it are the same job on
		-- every character and stay where they are.
		if ns.Layout.Plan() then
			LoadoutPage(ui)
		end

		ui.Section("Our own bars", "Fighting")
		ui.Lede("Stands up one of our bars for each of yours: same slots, same keys, Blizzard's hidden behind.")

		-- One row per bar the client can have, so a bar that misbehaves can be
		-- handed back on its own without turning the whole feature off and
		-- losing the others. Untouched, each row shows what you have on.
		for _, def in ipairs(ns.WhichBars.PLAN) do
			ui.Check(def.label,
				function() return ns.WhichBars.Wanted(def) end,
				function(value) SetBar(def, value) end)
		end
		ui.Action(
			function() return "match my current bars" end,
			Match,
			function() return ns.WhichBars.Decided() > 0 end)
		ui.Hint("A row left alone follows your own interface options, so turning a bar on there clones it too. Match puts every row back to following.")
		ui.Reading("cloning", function()
			if not ns.db.actionBars then
				return "off, your bars are Blizzard's"
			end
			return ns.Bars.Describe()
		end)
		ui.Reading("set by hand", function()
			local decided = ns.WhichBars.Decided()
			return decided == 0 and "none" or (decided .. " of the rows above")
		end)

		EachBarPage(ui)

		ui.Section("Spell ranks", "Fighting")
		ui.Lede("Moves any spell on a bar that is holding an old rank up to the best one you know.")
		ui.Action(
			function()
				local count = #ns.Ranks.Stale()
				return count > 0 and ("refresh spells (%d)"):format(count) or "refresh spells"
			end,
			RefreshRanks,
			function() return (ns.Ranks.CanApply()) and #ns.Ranks.Stale() > 0 end)
		ui.Hint("Macros, items and empty slots are left alone. Only a spell whose rank is behind what you have trained is moved.")
		ui.Reading("your bars", function()
			local can, why = ns.Ranks.CanApply()
			if not can then
				return why
			end
			return ns.Ranks.Describe()
		end)
	end,
})
