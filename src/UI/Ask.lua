local ADDON, ns = ...

local UI = ns.UI
local C, M = UI.Color, UI.Metric

--------------------------------------------------------------------------
-- One question, and two buttons
--
-- The addon asks a player to confirm exactly one kind of thing: something that
-- cannot be undone. Abandoning a quest is the first of them, and the shape of
-- the question is the same every time it is asked, so it is one window rather
-- than one per site.
--
-- **It replaces a button that arms itself.** The quest log used to abandon on
-- the second press of the same button, with a line in the chat window between
-- the two saying what the second press would do. That is a real confirmation
-- and it has two faults. The sentence is in a window you may not be looking at,
-- and the state is invisible: a button that says "abandon it" instead of
-- "abandon" is the whole of the warning, and a player who pressed once and got
-- distracted comes back to a button that is one click from throwing a quest
-- away. A window in the middle of the screen cannot be missed and cannot be
-- pressed by accident.
--
-- **One window, reused.** Every popup in this addon is built once and repainted,
-- for the reason UI/Widgets.lua's dropdown gives: this client cannot destroy a
-- frame, so a window made per question is a window leaked per question. It also
-- means two questions cannot be on the screen at once, which is the behaviour
-- you want: the second would cover the first and both would be about something
-- irreversible.
--
-- **What it does not do is take the mouse away from the game.** A real modal
-- dims the world and eats every click, and none of that is worth the frame
-- level fight on a client where another addon may be doing the same thing. The
-- question is on top, it has the two buttons, and closing it any other way is
-- the same answer as no.
--------------------------------------------------------------------------

local WIDTH = 320

-- The window, and what it is asking about right now. `asked` is nil whenever
-- nothing is on the screen, which is what makes UI.Asking answerable and what
-- stops a stale callback firing after the window has been closed some other way.
local window, asked = nil, nil

local function Close()
	asked = nil
	if window then
		window:Hide()
	end
end

-- Both buttons and the question between them. The accept is on the right, where
-- every other window in the addon puts the thing it is for, and it carries the
-- danger colour rather than a word in red: the colour is on the surface you are
-- about to press, which is the one place it cannot be misread as decoration.
local function Build()
	if window then
		return window
	end

	window = UI.Window({
		name = "WarriorKitAsk",
		title = "",
		width = WIDTH,
		height = M.title + M.footer + M.pad * 2 + M.row * 2,
		-- Over every other window in the addon rather than beside them. A
		-- question about something irreversible that opens behind the window
		-- that asked it is a window that has done nothing at all, and every
		-- other window here is on DIALOG.
		strata = "FULLSCREEN_DIALOG",
	})

	window.question = UI.Label(window.content, M.font, C.text, "LEFT", UI.FLAT)
	window.question:SetPoint("TOPLEFT", M.pad, -M.pad)
	window.question:SetWidth(WIDTH - M.pad * 2)
	UI.Wrap(window.question, true)
	window.question:SetSpacing(2)

	window.accept = UI.Button(window.footer, {
		label = "yes",
		width = 92,
		tone = C.danger,
		onClick = function() UI.Answer(true) end,
	})
	window.accept:SetPoint("RIGHT", 0, 0)

	window.refuse = UI.Button(window.footer, {
		label = "keep it",
		width = 76,
		onClick = function() UI.Answer(false) end,
	})
	window.refuse:SetPoint("RIGHT", window.accept, "LEFT", -M.rowGap, 0)

	-- Escape, the close box and anything else that takes the window off the
	-- screen are all the same answer, and it is no. Hung on the frame rather
	-- than on the method for the reason UI/Window.lua hangs its own cleanup
	-- there: UISpecialFrames calls Hide and knows nothing about this file.
	window.frame:HookScript("OnHide", function()
		asked = nil
	end)
	return window
end

--------------------------------------------------------------------------

-- Put a question up.
--
--   title     what the window is called
--   question  the sentence, which wraps
--   accept    the word on the button that does the thing
--   onAccept  called when that button is pressed, and never otherwise
--
-- Answers the question string, so a caller can say what it asked without
-- keeping its own copy.
function UI.Ask(opts)
	Build()
	asked = opts.question or ""

	window:SetTitle(opts.title or "")
	window.question:SetText(asked)
	window.accept.text:SetText(opts.accept or "yes")
	window.accept.onAccept = opts.onAccept

	-- Tall enough for the sentence it was given. A question is one line or
	-- three depending on how long the quest's name is, and a window sized for
	-- the longest of them is a window with a hole under most of its questions.
	window:Resize(WIDTH, M.title + M.footer + M.pad * 2
		+ UI.TextHeight(window.question, M.row))
	window:Show()
	return asked
end

-- The question on the screen now, or nil. Public because a part that put one up
-- has to be able to tell whether the player has dealt with it, and because it
-- is the only way a test can see the window without naming its frames.
function UI.Asking()
	return asked
end

-- Press one of the two buttons. Answers whether there was a question to answer,
-- which is not the same as whether the player said yes.
function UI.Answer(yes)
	if not asked then
		return false
	end
	local accept = yes and window.accept.onAccept or nil
	Close()
	if accept then
		accept()
	end
	return true
end
