local ADDON, ns = ...

local Trace = {}
ns.CharTrace = Trace

--------------------------------------------------------------------------
-- What a gear square did when you clicked it
--
-- Off, and worth nothing until it is on. `/wk character trace` turns it on and
-- every click on a square then says what the client was asked and what it
-- answered, in chat, in the order it happened.
--
-- **It exists because the square has been wrong three times and each time the
-- symptom was the same word: nothing.** A click that never reached the button,
-- a click that reached it and acted on the other edge, and a click that acted
-- and was refused all look identical from a chair. The three are told apart by
-- what appears here: no line at all means the click never arrived, a press line
-- with no release line means an error in between, and a BLOCKED line names the
-- call the client refused and which addon it blamed.
--
-- **Nothing here is allowed to break a click.** Every client call goes through
-- the pcall below, every line is built from what came back rather than assumed,
-- and the whole file is a no-op while it is off, because a trace that errors in
-- PreClick would take the square down with it and that is the thing being
-- diagnosed.
--------------------------------------------------------------------------

local on = false

-- The squares, keyed by the button, with what each one registered for. Recorded
-- at build rather than asked for at click time: this client has no call that
-- answers which edges a button took, so the only honest source is the file that
-- registered them.
local squares = {}

local function Ask(name, ...)
	local call = _G[name]
	if type(call) ~= "function" then
		return nil, false
	end
	local ok, value = pcall(call, ...)
	if not ok then
		return nil, true
	end
	return value, true
end

-- One client question, printed as `name=answer`, with the two failures kept
-- apart: a call this client does not have is not a call that answered no.
local function Answer(name, ...)
	local value, exists = Ask(name, ...)
	if not exists then
		return name .. "=absent"
	end
	return ("%s=%s"):format(name, tostring(value and true or false))
end

local function Say(line)
	ns.Print("gear " .. line)
end

--------------------------------------------------------------------------
-- The lines
--------------------------------------------------------------------------

-- Which edge this square's secure half acts on, worked out the way the client
-- works it out: the button's own attribute, and the player's setting where the
-- button does not answer. This is the line that mattered: a square registered
-- for the release while this says down is a square that draws and does nothing.
local function Edge(button)
	local keyDown = button:GetAttribute("useOnKeyDown")
	if keyDown ~= nil then
		return keyDown and "down" or "up", "useOnKeyDown attribute"
	end
	local cvar = Ask("GetCVarBool", "ActionButtonUseKeyDown")
	return cvar and "down" or "up", "ActionButtonUseKeyDown setting"
end

-- What the client is holding. SpellIsTargeting is the wider question and the
-- other two are the one the page acts on, so all three are said: a spell that is
-- waiting for something that is not an item reads as the first alone.
local function Waiting()
	return ("%s, %s, %s"):format(Answer("SpellIsTargeting"),
		Answer("SpellCanTargetItem"), Answer("SpellCanTargetItemID"))
end

-- What the secure half will read when it runs. The attributes rather than the
-- intent, because the intent is what was already believed.
local function Attributes(button, entry)
	return ("type1=%s type2=%s macrotext2=%s target-slot=%s"):format(
		tostring(button:GetAttribute("type1")),
		tostring(button:GetAttribute("type2")),
		tostring(button:GetAttribute("macrotext2")),
		tostring(button:GetAttribute("target-slot") or entry.slot))
end

-- Which frame the client says the mouse is on. The one line that separates a
-- click that never arrived from every other failure.
--
-- Asked with the bar trace's calls rather than a second copy of them: that file
-- already knows this call was renamed and that the addon runs on both clients,
-- and it names an anonymous frame by its parent, which is the case a copy here
-- would have got wrong.
local function Under()
	local frame = ns.BarTrace.Focus()
	return ns.BarTrace.Name(frame)
end

--------------------------------------------------------------------------
-- What the squares call
--------------------------------------------------------------------------

function Trace.Watch(button, entry, ...)
	squares[button] = { entry = entry, clicks = table.concat({ ... }, " ") }
end

function Trace.Press(button, which, down)
	if not on then
		return
	end
	local square = squares[button]
	if not square then
		return
	end
	local entry = square.entry
	local edge, source = Edge(button)
	Say(("%s (%d): %s %s, registered %s"):format(entry.label, entry.slot,
		tostring(which), down and "down" or "up", square.clicks))
	Say(("  acts on %s, by the %s; mouse on %s, cursor %s"):format(edge, source,
		Under(), ns.BarTrace.Cursor()))
	Say("  " .. Waiting())
	Say("  " .. Attributes(button, entry))
end

-- After the client's own half, which is the half that consumes a waiting spell.
-- The same three questions asked again, because the answer changing is the
-- proof that the click did something and the answer holding is the proof that
-- it did not.
function Trace.Release(button, which, swapped)
	if not on then
		return
	end
	local square = squares[button]
	if not square then
		return
	end
	Say(("  after: %s released, %s, cursor %s, swap %s"):format(tostring(which),
		Waiting(), ns.BarTrace.Cursor(), swapped and "ran" or "did not run"))
end

-- The other gesture, and the one a click trace cannot see. A drag out that
-- prints nothing is a drag the button never registered for; a drag that prints
-- and leaves the cursor empty is the swap refusing, which it does with a reason
-- of its own in chat.
function Trace.Drag(button, swapped)
	if not on then
		return
	end
	local square = squares[button]
	if not square then
		return
	end
	local entry = square.entry
	Say(("%s (%d): drag out, swap %s, cursor %s"):format(entry.label, entry.slot,
		swapped and "ran" or "did not run", ns.BarTrace.Cursor()))
end

--------------------------------------------------------------------------
-- The switch
--------------------------------------------------------------------------

-- The client's own complaint, which is the one thing here that is not about a
-- square. It names the addon it blamed and the call it refused, and the reason
-- this file exists at all is that the dialog on screen names neither.
local watcher = CreateFrame("Frame")
watcher:SetScript("OnEvent", function(_, event, addon, call)
	if not on then
		return
	end
	Say(("BLOCKED: %s tried %s (%s)"):format(tostring(addon),
		tostring(call), event))
end)

function Trace.Set(value)
	on = value and true or false
	if on then
		watcher:RegisterEvent("ADDON_ACTION_FORBIDDEN")
		watcher:RegisterEvent("ADDON_ACTION_BLOCKED")
	else
		watcher:UnregisterAllEvents()
	end
	return on
end

function Trace.On()
	return on
end

-- What the trace can see before anything is clicked. Printed when it is turned
-- on, because two of the three questions it answers do not need a click and one
-- of them was the bug.
function Trace.Describe()
	if not on then
		return "off"
	end
	local count = 0
	local edge, source = "no square built yet", "nothing"
	for button, square in pairs(squares) do
		count = count + 1
		if square.entry.slot == 16 then
			edge, source = Edge(button)
		end
	end
	return ("on, %d squares, main hand acts on %s by the %s; %s")
		:format(count, edge, source, Waiting())
end
