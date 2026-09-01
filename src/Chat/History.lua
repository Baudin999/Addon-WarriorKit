local ADDON, ns = ...

local History = {}
ns.ChatHistory = History

--------------------------------------------------------------------------
-- What was said, kept across a logout
--
-- Every other thing this part holds is a fact about the session: which rooms
-- are on the rail, what is unread in each, what is in a log. A reload threw
-- the lot away, and for the guild and the numbered channels that is right,
-- because nothing in either is addressed to you. For two rooms it is not. A
-- whisper is a conversation with one person and half of it is not one, and the
-- party chat you scrolled back through to find the summon location is gone the
-- moment an addon update makes you reload.
--
-- So those two are written down. This file is the record and nothing else: it
-- knows how to hold a line, when a line is too old to hold, and how many lines
-- are worth somebody's disk. Chat/Rooms.lua decides which lines those are,
-- because which room a line belongs to is its question, and Chat/Window.lua
-- draws what comes back.
--
-- **A day, and then it is gone.** Not a setting, and not a cap on its own. A
-- transcript kept for a week is a file that grows all week and a window that
-- opens on last Tuesday; a transcript kept for an hour is one that has thrown
-- away the summon location by the time you look for it. A day is the session
-- you just played and the one before it, which is the span anybody actually
-- scrolls back over, and it is also the span that makes the record safe to
-- keep at all: what is on this disk in a week's time is nothing.
--
-- **Per character.** A whisper is addressed to a character and the party you
-- were in was this one's, so it goes in WarriorKitCharDB beside the experience
-- tally and the damage record rather than in the account file beside the
-- groups.
--------------------------------------------------------------------------

-- How long a line is kept, and how many are kept at once.
--
-- The cap is the second half of the same promise and it is the one that holds
-- on a raid night: a day of a busy party is more lines than anybody scrolls
-- through, and a saved variables file is read and written whole at every login
-- and logout. Four hundred lines is about six screens of the window at its
-- shipped size, which is further back than the scroll wheel goes in one sweep.
local DAY = 24 * 60 * 60
local KEEP = 400

--------------------------------------------------------------------------
-- Where it is kept
--
-- Made on the way in rather than trusted to be there. The defaults hand every
-- character an empty pair at ADDON_LOADED, and a file edited by hand can hold
-- neither; a nil here is a line that raises inside an event handler, which is
-- the one place in this addon a raise is swallowed.
--------------------------------------------------------------------------

local function Log()
	local db = ns.dbc
	if not db then
		return nil
	end
	db.chatLog = db.chatLog or {}
	return db.chatLog
end

--------------------------------------------------------------------------
-- What is too old, and what is too much
--
-- Both answers are a count off the front, because the list is in the order the
-- lines arrived: everything before the first line inside the day goes, and so
-- does everything past the cap.
--
-- Compacted in one pass rather than by a table.remove for each. A login that
-- comes back to a day-old file drops the lot in one call, and doing that an
-- entry at a time would shift the array once per line dropped.
--------------------------------------------------------------------------

local function Prune(log)
	local cutoff = time() - DAY
	local first = 1
	while log[first] and (log[first].at or 0) < cutoff do
		first = first + 1
	end

	local over = (#log - first + 1) - KEEP
	if over > 0 then
		first = first + over
	end
	if first == 1 then
		return 0
	end

	local at = 1
	for index = first, #log do
		log[at] = log[index]
		at = at + 1
	end
	for index = at, #log do
		log[index] = nil
	end
	return first - 1
end

--------------------------------------------------------------------------
-- Writing
--------------------------------------------------------------------------

-- One line, on its way to the window. Called for every line drawn and it says
-- no to nearly all of them.
--
-- The room list is copied rather than kept. It is Chat/Rooms.lua's table, one
-- per line, and a saved variable holding somebody else's table is the aliasing
-- the settings layer already learned about the hard way.
function History.Note(rooms, line, r, g, b)
	local log = Log()
	if not log or type(line) ~= "string" or not ns.Rooms.Kept(rooms) then
		return false
	end

	local ids = {}
	for at, id in ipairs(rooms) do
		ids[at] = id
	end
	log[#log + 1] = { at = time(), line = line, r = r, g = g, b = b, rooms = ids }
	Prune(log)
	return true
end

-- Who you have been talking to, in the order the rail draws them.
--
-- Written whole rather than patched, because the list is eight names at most
-- and Chat/Rooms.lua moves a name to the front of it on every whisper. A
-- record kept in step with a list by editing both is a record that goes out of
-- step; a record rewritten wherever that order moves cannot.
--
-- Names only. The key a room is filed under is worked out from the name, and
-- writing it down as well would be two spellings of one fact in a file that
-- outlives the code that wrote it.
function History.Talked(list)
	local db = ns.dbc
	if not db then
		return false
	end
	local out = {}
	for at, entry in ipairs(list) do
		out[at] = entry.name
	end
	db.chatWith = out
	return true
end

--------------------------------------------------------------------------
-- Reading
--------------------------------------------------------------------------

-- Everything worth bringing back, purged first. The conversations in rail
-- order, then the lines in the order they arrived.
--
-- A conversation with nothing left inside the day is dropped here rather than
-- handed back, because the room it would draw is an empty row with somebody's
-- name on it, and the rail is the one part of this window that must never say
-- there is something to read when there is not.
function History.Read()
	local log = Log()
	if not log then
		return {}, {}
	end
	Prune(log)

	local alive = {}
	for _, held in ipairs(log) do
		for _, id in ipairs(held.rooms or {}) do
			alive[id] = true
		end
	end

	local talked = {}
	for _, name in ipairs(ns.dbc.chatWith or {}) do
		local id = type(name) == "string" and ns.Rooms.WhisperId(name)
		if id and alive[id] then
			talked[#talked + 1] = name
		end
	end
	ns.dbc.chatWith = talked
	return talked, log
end

--------------------------------------------------------------------------
-- Emptying it
--
-- Reachable from `/wk chat forget` and from nowhere else. In particular the
-- window's own reset does not come here: that button is about where the window
-- sits and how big it is, and a control about the layout has no business
-- throwing away what somebody said to you.
--------------------------------------------------------------------------

function History.Wipe()
	local db = ns.dbc
	if not db then
		return false
	end
	db.chatLog, db.chatWith = {}, {}
	return true
end

function History.Describe()
	local db = ns.dbc
	if not db then
		return "nothing saved yet"
	end
	local lines = #(db.chatLog or {})
	if lines == 0 then
		return "nothing kept from before"
	end
	local talked = #(db.chatWith or {})
	return ("%d lines kept for a day, over %d %s"):format(lines, talked,
		talked == 1 and "conversation" or "conversations")
end
