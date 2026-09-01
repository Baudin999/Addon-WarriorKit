-- What survives a logout
--
-- Four questions, and every one of them is about a file rather than a frame,
-- which is why none of them can be answered by looking at the window.
--
-- Is the right thing written down. Two rooms out of the thirteen are worth a
-- day of somebody's disk, and both ways of getting that wrong are silent: a
-- record that keeps everything is a saved variables file that grows all night
-- and a login that reads it back whole, and one that keeps nothing looks
-- exactly like a working addon until the reload.
--
-- Does a day actually end. The purge is the whole of the promise that this is
-- safe to keep at all, and nothing on a screen ever shows it running.
--
-- Does the cap hold. It is the half of that promise that matters on a raid
-- night, when a day of a busy party is more lines than the file should carry.
--
-- And does what comes back come back where it was said, including the room
-- that is no longer there. A group deleted between sessions leaves lines filed
-- under a room the rail will never draw, and a log in this client is a frame
-- nothing can destroy.

local H = ...
local ns, fire, check = H.ns, H.fire, H.check
local Rooms, History = ns.Rooms, ns.ChatHistory

local DAY = 24 * 60 * 60

-- The record from the login, out of the way. The sections above this one have
-- been firing chat at the window all run and what they left behind is not what
-- any of this is about.
History.Wipe()
Rooms.Wipe()

local function whisper(who, what)
	fire("CHAT_MSG_WHISPER", what, who, nil, nil, nil, nil, nil, nil, nil, nil, nil, "H1")
end

----------------------------------------------------------------------
-- Which lines are worth keeping
----------------------------------------------------------------------

do
	whisper("Aria", "where are you")
	check(#ns.dbc.chatLog == 1, "a whisper was not written down")

	fire("CHAT_MSG_PARTY", "summon at the stone", "Bram",
		nil, nil, nil, nil, nil, nil, nil, nil, nil, "H2")
	check(#ns.dbc.chatLog == 2, "a party line was not written down")

	local kept = #ns.dbc.chatLog
	fire("CHAT_MSG_SAY", "hello", "Stranger", nil, nil, nil, nil, nil, nil, nil, nil, nil, "H3")
	fire("CHAT_MSG_GUILD", "wts", "Stranger", nil, nil, nil, nil, nil, nil, nil, nil, nil, "H3")
	fire("CHAT_MSG_RAID", "pull", "Stranger", nil, nil, nil, nil, nil, nil, nil, nil, nil, "H3")
	check(#ns.dbc.chatLog == kept,
		("say, guild and raid put %d lines in a record that keeps whispers and the party")
			:format(#ns.dbc.chatLog - kept))

	-- The line is filed under every room it reached, Conversation included, so
	-- what comes back comes back in all of them rather than only in the one
	-- that earned it a place in the file.
	local held = ns.dbc.chatLog[2]
	local rooms = {}
	for _, id in ipairs(held.rooms) do
		rooms[id] = true
	end
	check(rooms[Rooms.ALL] and rooms.party,
		"a party line was filed under something other than the party and Conversation")
	check(held.at and held.at > 0, "a kept line carries no time")
	check(held.line:find("summon at the stone", 1, true) ~= nil,
		"a kept line is not the line that was drawn")

	-- And the conversation, by name, in the order the rail draws it.
	whisper("Bruk", "on my way")
	check(ns.dbc.chatWith[1] == "Bruk" and ns.dbc.chatWith[2] == "Aria",
		"the saved conversations are not in the order the rail draws them")
end

----------------------------------------------------------------------
-- A day, and then it is gone
----------------------------------------------------------------------

do
	for _, held in ipairs(ns.dbc.chatLog) do
		held.at = time() - DAY - 60
	end
	local stale = #ns.dbc.chatLog
	check(stale > 0, "nothing was there to go stale")

	whisper("Aria", "still here")
	check(#ns.dbc.chatLog == 1,
		("%d lines survived a day when only the new one should have")
			:format(#ns.dbc.chatLog))

	-- And a conversation with nothing left inside the day comes off the rail
	-- with its lines, because a row with a name on it and an empty log behind
	-- it is the one thing the rail must never say.
	Rooms.Wipe()
	ns.dbc.chatWith = { "Aria", "Gone" }
	local talked = History.Read()
	check(#talked == 1 and talked[1] == "Aria",
		"a conversation with nothing left inside the day was kept")
end

----------------------------------------------------------------------
-- The cap
----------------------------------------------------------------------

do
	History.Wipe()
	Rooms.Wipe()
	for index = 1, 500 do
		whisper("Aria", "line " .. index)
	end
	local kept = #ns.dbc.chatLog
	check(kept < 500 and kept > 0,
		("five hundred whispers left %d lines and nothing capped them"):format(kept))
	check(ns.dbc.chatLog[kept].line:find("line 500", 1, true) ~= nil,
		"the cap threw away the newest lines rather than the oldest")
end

----------------------------------------------------------------------
-- What comes back
----------------------------------------------------------------------

do
	History.Wipe()
	Rooms.Wipe()
	whisper("Aria", "where are you")
	fire("CHAT_MSG_PARTY", "at the stone", "Bram",
		nil, nil, nil, nil, nil, nil, nil, nil, nil, "H2")

	-- A line filed under a room nothing answers for any more. In the game that
	-- is a group deleted between sessions; here it is written straight into the
	-- record, because what is being checked is the reader.
	ns.dbc.chatLog[1].rooms[#ns.dbc.chatLog[1].rooms + 1] = "group:nosuchgroup"

	Rooms.Wipe()
	local lines = Rooms.Restore()
	check(#lines == 2, ("%d lines came back out of two"):format(#lines))

	local aria = Rooms.WhisperId("Aria")
	check(Rooms.Exists(aria), "a conversation did not come back onto the rail")
	check(Rooms.Recent() == "Aria", "the reply key does not answer the restored conversation")

	local seen = {}
	for _, held in ipairs(lines) do
		for _, id in ipairs(held.rooms) do
			seen[id] = true
		end
	end
	check(seen[aria] and seen.party and seen[Rooms.ALL],
		"a restored line lost the room it was said in")
	check(not seen["group:nosuchgroup"],
		"a line came back into a room there is no longer any such thing as")

	-- The party room is on the rail with nothing in the party, which is the
	-- point: the group is last night's and the conversation is not.
	check(Rooms.Exists("party"),
		"the party room holds last night's lines and is not on the rail")

	-- Once. The window is built again whenever the part is turned back on, and
	-- a second pass would draw the evening twice.
	check(#Rooms.Restore() == 0, "a second restore handed the same lines back again")
end

print(("chat   %s; whispers and the party survive a logout, %d hours and then gone")
	:format(History.Describe(), DAY / 3600))

History.Wipe()
Rooms.Wipe()
