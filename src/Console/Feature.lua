local ADDON, ns = ...

-- The console page and the word that reaches it. Console.lua runs the code;
-- this file draws the box it is typed into, the button per probe, and the
-- lines that came back.

local Console = ns.Console

-- How much of an answer the page draws. Past this the rest goes to the chat
-- window, which scrolls, rather than to a box that would have to.
local LINES_SHOWN = 10

-- The box is sized for the longest probe with a line to spare, and the
-- output for LINES_SHOWN lines of the small face plus the line that says
-- there were more.
local EDITOR_LINES = 9

-- The one box and the one readout, held so the word and the buttons can write
-- into them. Built once, when the panel builds the page.
local page = {}

local function Show(lines)
	page.lines = lines
	if not page.output then
		return
	end
	local shown = {}
	for index = 1, math.min(#lines, LINES_SHOWN) do
		shown[index] = lines[index]
	end
	if #lines > LINES_SHOWN then
		shown[#shown + 1] = ("and %d more, in the chat window"):format(#lines - LINES_SHOWN)
	end
	page.text = table.concat(shown, "\n")
	page.output:SetText(page.text)
	page.output:SetCursorPosition(0)
end

-- Run, show, and send to chat whatever the page could not fit.
local function Run(code)
	local lines = Console.Run(code)
	Show(lines)
	for index = LINES_SHOWN + 1, #lines do
		ns.Print(lines[index])
	end
	return lines
end

--------------------------------------------------------------------------

local ConsoleWord = ns.Command.Word({
	name = "console",
	show = function()
		ns.Options.Show()
		return "the console is on the panel, under Under the hood.",
			"  console run <lua> runs a line from here, and console "
				.. Console.Names() .. " runs a probe."
	end,

	-- The code is taken raw. The runner lowercases the first word for
	-- matching and that word is either `run` or a probe's name, so nothing a
	-- case matters in is read off the lowered copy.
	otherwise = function(option, _, rawValue)
		local code
		if option == "run" then
			code = rawValue
			if code == "" then
				ns.Print("console run takes a line of Lua after it.")
				return
			end
		else
			local probe = Console.Probe(option)
			if not probe then
				ns.Print(("no probe called %q. The probes are %s.")
					:format(option, Console.Names()))
				return
			end
			code = probe.code
		end
		local lines = Console.Run(code)
		Show(lines)
		for index = 1, #lines do
			ns.Print(lines[index])
		end
	end,
})

--------------------------------------------------------------------------

local function BuildEditor(row)
	local UI = ns.UI
	local M, C = UI.Metric, UI.Color
	local box = UI.Box(row, C.sunken, C.edge)
	box:SetAllPoints()

	local edit = CreateFrame("EditBox", nil, box)
	edit:SetMultiLine(true)
	edit:SetPoint("TOPLEFT", 4, -2)
	edit:SetPoint("BOTTOMRIGHT", -4, 2)
	edit:SetFontObject(UI.Font(M.font, UI.FLAT))
	edit:SetTextColor(C.text[1], C.text[2], C.text[3])
	edit:SetAutoFocus(false)
	edit:SetMaxLetters(4000)
	edit:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	edit:SetScript("OnEditFocusGained", function(self)
		UI.CloseDropdown()
		UI.StopCapture()
		UI.Typing(self)
		UI.Tint(box.bg, C.selected)
	end)
	edit:SetScript("OnEditFocusLost", function()
		UI.StopTyping()
		UI.Tint(box.bg, C.sunken)
	end)
	edit:SetScript("OnHide", function(self)
		self:ClearFocus()
	end)
	page.edit = edit
	return nil
end

-- The readout is a field rather than a label, because the client has no
-- clipboard call and the one way text leaves the game is Ctrl-C over a
-- selection in a field that holds the keyboard. It draws as the label did,
-- and anything typed over it is put back, so what it shows is always what the
-- last run printed and never a line someone's Ctrl-V landed in.
local function BuildOutput(row)
	local UI = ns.UI
	local M, C = UI.Metric, UI.Color
	local box = UI.Box(row, C.sunken, C.edge)
	box:SetAllPoints()

	local edit = CreateFrame("EditBox", nil, box)
	edit:SetMultiLine(true)
	edit:SetPoint("TOPLEFT", 4, -3)
	edit:SetPoint("BOTTOMRIGHT", -4, 3)
	edit:SetFontObject(UI.Font(M.small, UI.FLAT))
	edit:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
	edit:SetAutoFocus(false)
	edit:SetScript("OnTextChanged", function(self, userInput)
		if userInput then
			self:SetText(page.text or "")
		end
	end)
	edit:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	edit:SetScript("OnEditFocusGained", function(self)
		UI.CloseDropdown()
		UI.StopCapture()
		UI.Typing(self)
	end)
	edit:SetScript("OnEditFocusLost", function()
		UI.StopTyping()
	end)
	edit:SetScript("OnHide", function(self)
		self:ClearFocus()
	end)
	page.output = edit
	Show(page.lines or { "nothing run yet" })
	return nil
end

-- The copy button. Puts the keyboard in the readout and selects the whole of
-- it, which is as far as an addon can take a copy; the Ctrl-C is yours. The
-- field is handed back so the harness can read what was selected.
local function Select()
	local out = page.output
	if not out then
		return nil
	end
	out:SetFocus()
	out:HighlightText()
	return out
end

ns.Register({
	name = "console",
	order = 32,

	words = {
		console = ConsoleWord,
	},

	help = {
		"console, the page. console xp, a probe. console run <lua>, one line of Lua",
	},

	status = function()
		if not page.lines then
			return "nothing run yet"
		end
		return ("%d lines from the last run"):format(#page.lines)
	end,

	panel = function(ui)
		local M = ns.UI.Metric
		ui.Section("Console", "Under the hood")
		ui.Lede("A few lines of Lua, run inside the game, and what they printed.")

		ui.Custom(BuildEditor, {
			height = EDITOR_LINES * (M.font + 2) + 4,
			label = "the lines to run",
		})

		ui.Action(function() return "run it" end, function()
			Run(page.edit and page.edit:GetText() or "")
		end)

		for index = 1, #Console.PROBES do
			local probe = Console.PROBES[index]
			ui.Action(function() return "probe " .. probe.label end, function()
				if page.edit then
					page.edit:SetText(probe.code)
				end
				Run(probe.code)
			end)
		end

		ui.Custom(BuildOutput, {
			height = (LINES_SHOWN + 1) * (M.small + 2) + 6,
			label = "what it printed",
			refresh = function()
				Show(page.lines or { "nothing run yet" })
			end,
		})
		ui.Action(function() return "select the result, then Ctrl-C copies it" end, Select)
		ui.Hint("Lines past the tenth go to the chat window.")
	end,
})
