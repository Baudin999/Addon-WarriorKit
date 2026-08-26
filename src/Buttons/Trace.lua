local ADDON, ns = ...

local Trace = {}
ns.BarTrace = Trace

--------------------------------------------------------------------------
-- What the mouse is really touching
--
-- Bar 1 has now refused two fixes, and both were written by reading the code.
-- The first raised the cloned bars above Blizzard's own mouse enabled bar
-- frame, which was a real bug and was not this one: the squares hover, name
-- what is on them and push under a click, so the mouse reaches them. A frame
-- that answers OnEnter is a frame the cursor is over, and a drop that lands
-- nowhere on that same square is therefore not a hit test at all.
--
-- The evening this cost was spent on theories that could not be checked. This
-- file is the answer to that: it prints what the client says, not what the code
-- says, so the next fix is chosen with the client's own answer in hand.
--
-- Two instruments, both read only, both off unless asked for:
--
--   The frame under the cursor, sampled a few times a second and printed when
--   it changes, with its strata and level and whether the cursor is holding
--   anything. Drag a spell across bar 1 with this on and the client names
--   whichever frame is taking the drop, which is a name no amount of reading
--   was going to produce.
--
--   Every gesture a square gets, printed by Buttons/Square.lua as it happens:
--   the slot, what the cursor held before, and what it holds after. A drop that
--   never prints is a drop the client never sent us; a drop that prints and
--   leaves the cursor loaded is PlaceAction refusing the slot. Those are
--   different bugs and nothing on screen has ever told them apart.
--
-- Nothing here writes anything. The worst it can do is talk too much, which is
-- why it is a switch and why the switch is not saved: a trace left on across a
-- login is a chat frame nobody can read, and this is a tool for one session
-- with a question in it.
--------------------------------------------------------------------------

-- Five a second. Fast enough that walking a spell across a bar prints every
-- frame it crossed, slow enough that the line does not repeat while the cursor
-- sits still, which the change guard below already covers anyway.
local INTERVAL = 0.2

local running = false
local since = 0
local last

local STRATA_UNKNOWN = "?"

-- A frame, said in the two things that decide who gets the mouse. The name
-- first, because that is what a fix has to name, and the parent's name after it
-- when the frame has none of its own: Blizzard's furniture is full of anonymous
-- children and "unnamed on MainMenuBar" is still an answer.
function Trace.Name(frame)
	if not frame then
		return "nothing"
	end

	local name = type(frame.GetName) == "function" and frame:GetName()
	if not name or name == "" then
		local parent = type(frame.GetParent) == "function" and frame:GetParent()
		local owner = parent and type(parent.GetName) == "function" and parent:GetName()
		local kind = type(frame.GetObjectType) == "function" and frame:GetObjectType() or "frame"
		name = owner and ("unnamed " .. kind .. " on " .. owner) or ("unnamed " .. kind)
	end

	local strata = type(frame.GetFrameStrata) == "function" and frame:GetFrameStrata() or STRATA_UNKNOWN
	local level = type(frame.GetFrameLevel) == "function" and frame:GetFrameLevel() or -1
	return ("%s (%s %d)"):format(name, strata or STRATA_UNKNOWN, level or -1)
end

-- What the cursor is carrying, in the three fields that matter to a drop. A
-- drop is a cursor before and a cursor after, and this is what both are read
-- with, so the two lines are comparable by eye.
function Trace.Cursor()
	if type(GetCursorInfo) ~= "function" then
		return "no cursor api"
	end
	local kind, first, second = GetCursorInfo()
	if not kind then
		return "empty"
	end
	return ("%s %s/%s"):format(tostring(kind), tostring(first), tostring(second))
end

-- The frame the client says the cursor is over, whichever way this client
-- answers that question.
--
-- Two names, because the first run of this trace printed nothing at all on the
-- live client and a silent instrument is worse than no instrument. GetMouseFocus
-- is the call every client from vanilla to Dragonflight had; GetMouseFoci
-- replaced it and returns the whole stack under the cursor, topmost first. This
-- client is a hybrid, so it is asked for both and neither is assumed.
--
-- Returns the frame and the name of the call that answered, so Trace.Set can
-- say up front which one this client has and a run that prints nothing is a run
-- that said why.
function Trace.Focus()
	if type(GetMouseFocus) == "function" then
		return GetMouseFocus(), "GetMouseFocus"
	end
	if type(GetMouseFoci) == "function" then
		local stack = GetMouseFoci()
		if type(stack) == "table" then
			return stack[1], "GetMouseFoci"
		end
		return stack, "GetMouseFoci"
	end
	return nil, nil
end

-- Which action slot a frame presses, when it is the kind of frame that presses
-- one. Blizzard's own buttons carry it too, so a trace that lands on one of
-- theirs says which slot theirs would have written and ours would have.
function Trace.Slot(frame)
	if type(frame) ~= "table" or type(frame.GetAttribute) ~= "function" then
		return nil
	end
	local ok, slot = pcall(frame.GetAttribute, frame, "action")
	if ok and type(slot) == "number" then
		return slot
	end
	return nil
end

function Trace.Running()
	return running
end

-- One line, and only while the switch is on. Every caller is a gesture that
-- happened once, so nothing here is on a tick and nothing is rate limited.
function Trace.Say(line)
	if not running then
		return
	end
	ns.Print("trace: " .. line)
end

--------------------------------------------------------------------------
-- The sampler
--
-- On its own frame rather than on the bars' ticker, because it has to keep
-- running with every bar hidden and because a diagnostic must never be able to
-- change the timing of the thing it is diagnosing.
--------------------------------------------------------------------------

local watcher = CreateFrame("Frame")

-- Named and listed in check.sh's HOT, which bans an unguarded write and an
-- allocation on any path an OnUpdate reaches. Both guards here are the same
-- one: nothing past the change test runs while the cursor sits still, and the
-- string the line is built from is behind it.
function Trace.Sample(_, elapsed)
	if not running then
		return
	end
	since = since + (elapsed or 0)
	if since < INTERVAL then
		return
	end
	since = 0

	local focus = Trace.Focus()
	if focus == last then
		return
	end
	last = focus
	local slot = Trace.Slot(focus)
	Trace.Say(("under the cursor: %s%s, holding %s"):format(
		Trace.Name(focus), slot and (", action " .. slot) or "", Trace.Cursor()))
end

watcher:SetScript("OnUpdate", Trace.Sample)

-- On or off, and it says which so the switch cannot be pressed twice by
-- mistake. The sample state is dropped on the way in rather than on the way
-- out, so turning it on always prints the first thing the cursor is over
-- instead of staying quiet because that frame was the last one seen.
function Trace.Set(on)
	running = on and true or false
	since = INTERVAL
	last = nil
	if running then
		-- Said on the way in rather than discovered by its absence. The first
		-- run of this printed every gesture and never once named a frame, and
		-- from the chat frame that looked exactly like a cursor that touched
		-- nothing rather than a client with no call to ask.
		local _, api = Trace.Focus()
		Trace.Say(api and ("the frame under the cursor is read with " .. api)
			or "this client has neither GetMouseFocus nor GetMouseFoci, so nothing can say which frame the cursor is over")
	end
	return running
end

-- What the trace is for, in the shape the answer will arrive in. Printed with
-- the switch, because a tool nobody knows how to read is a tool nobody uses.
function Trace.Describe()
	if not running then
		return "off"
	end
	return "on, printing the frame under the cursor and every gesture a square gets"
end
