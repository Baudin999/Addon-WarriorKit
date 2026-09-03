local ADDON, ns = ...

local Copy = {}
ns.ChatCopy = Copy

local UI = ns.UI
local C, M = UI.Color, UI.Metric

--------------------------------------------------------------------------
-- Copying what was said
--
-- The client has no clipboard call. The one way text leaves the game is
-- Ctrl-C over a selection in an edit box that holds the keyboard, and a
-- ScrollingMessageFrame is not one: you can read it and you cannot select a
-- word of it. So this is a second window with one field in it, filled with
-- the room you were reading, selected whole, waiting for the key.
--
-- One window, reused, for the reason UI/Ask.lua gives: this client cannot
-- destroy a frame, so a window per copy is a window leaked per copy. And one
-- room at a time rather than everything, because "what was said" is a room's
-- question. Conversation holds every line anybody said, System holds what the
-- game said, and the WarriorKit room holds what this addon said, so copying
-- the room you are in is copying whichever of those you meant.
--
-- The field is not a place to type. Anything typed over it is put back, the
-- way the console's readout does it, so what the box shows is always the log
-- and never a line somebody's Ctrl-V landed in.
--------------------------------------------------------------------------

local FRAME_NAME = "WarriorKitChatCopy"
local WIDTH, HEIGHT = 480, 320

-- One line of the field, in the window's own units. The font plus the spacing
-- a multi-line edit box puts between lines, and it is how tall the field is
-- told it is: the field reports no height of its own worth reading, and the
-- scroll view needs one to know whether there is anything below the fold.
local LINE = M.font + 2

local window, view, edit, text

local function Held()
	return text or ""
end

local function Build()
	if window then
		return window
	end
	window = UI.Window({
		name = FRAME_NAME,
		title = "Copy",
		width = WIDTH,
		height = HEIGHT,
		footer = 0,
	})

	view = UI.ScrollView(window.content)
	view.frame:SetPoint("TOPLEFT", M.pad, -M.pad)
	view:Resize(WIDTH - M.pad * 2, window:Body() - M.pad * 2)

	edit = CreateFrame("EditBox", nil, view.canvas)
	edit:SetMultiLine(true)
	edit:SetPoint("TOPLEFT")
	edit:SetPoint("TOPRIGHT")
	edit:SetFontObject(UI.Font(M.font, UI.FLAT))
	edit:SetTextColor(C.text[1], C.text[2], C.text[3])
	edit:SetAutoFocus(false)
	-- No cap. The default is the client's, and it is a few hundred letters
	-- where a room is a few hundred lines.
	if type(edit.SetMaxLetters) == "function" then
		edit:SetMaxLetters(0)
	end
	edit:SetScript("OnTextChanged", function(self, userInput)
		if userInput then
			self:SetText(Held())
		end
	end)
	edit:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
		window:Hide()
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
	return window
end

-- The room, in the box, selected. Returns the field so the harness can read
-- what was selected, and nil with the reason where there was nothing to copy.
function Copy.Show(title, lines)
	if type(lines) ~= "table" then
		return nil, "this client will not hand the log back"
	end
	if #lines == 0 then
		return nil, "nothing in this room yet"
	end
	Build()
	text = table.concat(lines, "\n")
	window:SetTitle(("Copy %s"):format(title or "chat"))
	edit:SetText(text)
	edit:SetHeight(#lines * LINE + M.rowGap)
	view:Update(#lines * LINE + M.rowGap)
	view:ScrollTo(0)
	window:Show()
	edit:SetFocus()
	edit:HighlightText()
	return edit
end

function Copy.Hide()
	if window then
		window:Hide()
	end
	return true
end

function Copy.Shown()
	return window ~= nil and window:IsShown() and true or false
end
