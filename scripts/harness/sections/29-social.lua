-- The social part
--
-- Five questions no amount of reading Chat/ will answer.
--
-- Does a line reach the rooms it belongs in, and only those. The whole feature
-- is a routing decision made once per message, and the two ways it can be
-- wrong, everything in one room and nothing in the group's, look identical in
-- the source and identical on a screenshot of an empty window.
--
-- Does the room you are reading decide where the line you type goes. That is
-- the redesign in one sentence, and it is one thing in three places: the slash
-- the field is filled in with, the note above the log that says what enter will
-- do, and the send itself.
--
-- Does the claim on Blizzard's frames come back off. It is a filter added to a
-- FrameXML list, and a filter that is added twice or never removed is a chat
-- window that goes quiet and stays quiet until a reload.
--
-- Does hiding Blizzard's window put it back. That one has teeth: with the
-- window hidden and the forward broken, every line of loot, experience and
-- addon output in the game is drawn nowhere at all.
--
-- Voice is not one of them any more. It is a Battle.net service rather than a
-- chat room and it is 41-voice.lua now, which is what took this file back under
-- the eight hundred line budget.
--
-- And does a client that refuses a ScrollingMessageFrame, or refuses one of the
-- two spellings of its insert mode, cost the log rather than the window.

local H = ...
local chat, group, advance = H.chat, H.group, H.advance
local ns, fire, check = H.ns, H.fire, H.check

local Feed, People, Window = ns.ChatFeed, ns.People, ns.ChatWindow
local Rooms, Compose, Voice = ns.Rooms, ns.Compose, ns.Voice

check(_G.WarriorKitChat ~= nil, "no chat window was built at login")
check(Window.Built(), "the chat window says it was not built")
check(_G.WarriorKitChat:GetWidth() == ns.db.chatWidth,
	("the chat window is %s wide and the setting says %s")
		:format(tostring(_G.WarriorKitChat:GetWidth()), tostring(ns.db.chatWidth)))

-- The rail down the left, and the room behind it. Two numbers rather than a
-- screenshot: the column is a fixed width and everything else in the window is
-- laid out against it, so a rail that came out at nothing would put the log
-- under itself and nothing else here would notice.
local M = ns.UI.Metric
check(_G.WarriorKitChatRooms:GetWidth() == M.rooms,
	("the room rail is %s wide and the theme says %d")
		:format(tostring(_G.WarriorKitChatRooms:GetWidth()), M.rooms))
-- And a row of it is wide enough to hold the icon that is the only thing on it.
-- The rail is a column of pictures now, so a row narrower than a picture is a
-- rail that draws nothing at all, and the width above is still correct while it
-- happens.
check(Window.Rail() >= M.roomIcon,
	("a room row came out %d wide and the icon on it is %d")
		:format(Window.Rail(), M.roomIcon))

-- The window has no title bar, so the rail gets everything the entry strip at
-- the foot and the voice button under it do not take. The voice button is in
-- the rail's own column and is the reason for the second subtraction: a rail
-- still measuring the full body would be drawing its last room underneath it.
check(_G.WarriorKitChatRooms:GetHeight() == ns.db.chatHeight - M.entry - M.roomRow,
	("the room rail is %s tall in a %d window, which has no title bar and a "
		.. "voice button in the rail's column")
		:format(tostring(_G.WarriorKitChatRooms:GetHeight()), ns.db.chatHeight))

----------------------------------------------------------------------
-- Which rooms exist
--
-- A room is drawn when the channel behind it exists. Standing alone with no
-- guild, that is Conversation and Say and nothing else: a party room with no
-- party would type into a channel the server refuses.
----------------------------------------------------------------------

check(People.Count() == 0, "the groups did not ship empty")
check(Window.Rooms() == 3,
	("%d rooms standing alone with no guild, expected Conversation, System and Say")
		:format(Window.Rooms()))
check(Window.Room() == Rooms.ALL,
	("the window opened in %s, expected everything"):format(tostring(Window.Room())))

-- The party, out of the same fixture UnitFrames/Group.lua is measured against,
-- so there is one model of a group in the suite rather than two that can
-- disagree about who party2 is.
local PARTY = {
	{ name = "Bram", class = "WARRIOR", guid = "P1" },
	{ name = "Aria", class = "PRIEST", guid = "P2" },
	{ name = "You", class = "WARRIOR", token = "player", you = true },
}
group.Set(PARTY)
fire("GROUP_ROSTER_UPDATE")
check(Window.Rooms() == 4, ("%d rooms in a party, expected a party room to appear")
	:format(Window.Rooms()))
check(Window.Go("party"), "the party room could not be selected")

group.Set(PARTY, true)
fire("GROUP_ROSTER_UPDATE")
check(Window.Rooms() == 5, ("%d rooms in a raid, expected a raid room as well")
	:format(Window.Rooms()))
chat.inGuild = true
fire("PLAYER_GUILD_UPDATE")
check(Window.Rooms() == 6, ("%d rooms in a guild, expected a guild room as well")
	:format(Window.Rooms()))

-- Back to a party for the rest of it. The raid room has been seen to appear and
-- everything below walks party tokens, which are not what a raid hands out.
group.Set(PARTY)
fire("GROUP_ROSTER_UPDATE")

----------------------------------------------------------------------
-- The groups
----------------------------------------------------------------------

check(People.AddGroup("Family") == 1, "the first group was not made")
check(Window.Rooms() == 6, ("%d rooms with a group named, expected one more")
	:format(Window.Rooms()))

check(People.Add(1, "Aria") == 1, "the first name did not go into the group")
check(People.Match("aria") ~= nil, "a name matched only in the case it was typed")
check(People.Match("Aria-Firemaw") ~= nil, "a realm suffix stopped a name matching")
check(People.Match("Ariax") == nil, "a name that is not in a group matched anyway")
check(People.Add(1, "ARIA-Nethergarde") == nil,
	"the same person went into one group twice under a different realm")

-- The same person in two groups is the point rather than a mistake: a line goes
-- to both rooms.
check(People.AddGroup("Guildies") == 2, "the second group was not made")
check(People.Add(2, "Aria") == 1, "the same person could not be in two groups")
check(#People.Match("Aria") == 2,
	("Aria is matched in %d groups, expected both"):format(#People.Match("Aria")))
People.RemoveGroup(2)
check(#People.Match("Aria") == 1, "deleting a group left its people matched by it")

-- Everyone with you, in one press. Three party tokens, one of them already in
-- the group, because the button has to be pressable twice.
local added, skipped = People.AddParty(1)
check(added == 1 and skipped == 1,
	("adding the party added %d and skipped %d, expected one of each")
		:format(added, skipped))
check(People.Total() == 2, ("the group holds %d, expected 2"):format(People.Total()))

local family = "group:" .. People.Get(1).key

----------------------------------------------------------------------
-- Routing
--
-- Counted off the rooms themselves rather than off a sink installed for the
-- test, because what is being asserted is where a line landed and a test sink
-- would be asserting that the feed called the test sink.
----------------------------------------------------------------------

do
	local function held()
		return Window.Count(Rooms.ALL), Window.Count("party"), Window.Count(family)
	end

	local all, party, mine = held()
	fire("CHAT_MSG_PARTY", "pull it", "Stranger", nil, nil, nil, nil, nil, nil, nil, nil, nil, "GX")
	local a, b, c = held()
	check(a == all + 1, "a party line from a stranger did not reach Conversation")
	check(b == party + 1, "a party line did not reach the party room")
	check(c == mine, "a party line from a stranger reached a group room")

	fire("CHAT_MSG_PARTY", "coming", "Bram", nil, nil, nil, nil, nil, nil, nil, nil, nil, "P1")
	local d, e, f = held()
	check(d == a + 1 and e == b + 1, "a party line from somebody in a group missed the party room")
	check(f == c + 1, "a party line from somebody in a group missed that group's room")

	-- A whisper is in three places at once, and the third is a room named after
	-- the person that did not exist a moment ago.
	local whisper = Rooms.WhisperId("Aria")
	check(Window.Count(whisper) == 0, "a room for Aria existed before she said anything")
	fire("CHAT_MSG_WHISPER", "where are you", "Aria", nil, nil, nil, nil, nil, nil, nil, nil, nil, "P2")
	local g, _, i = held()
	check(g == d + 1, "a whisper did not reach Conversation")
	check(i == f + 1, "a whisper from somebody in a group did not reach that group's room")
	check(Window.Count(whisper) == 1, "a whisper did not open a room with that person")

	-- And that room's log is the size of every other room's.
	--
	-- A log is made on the first line that lands in it, which for a room that
	-- did not exist a moment ago is long after the window laid itself out. The
	-- version of this that shipped placed the logs it knew about and left every
	-- later one anchored to nothing at no size: the lines went into the buffer,
	-- the count in the rail went up, and the room drew nothing. Say was the room
	-- that showed it, because the first thing you say all evening is what makes
	-- its log.
	local wide, tall = Window.Shape(whisper)
	local roomWide, roomTall = Window.Shape(Rooms.ALL)
	check(wide == roomWide and tall == roomTall,
		("a room made after the window was laid out came out %sx%s, and the "
			.. "rooms laid out with it are %sx%s")
			:format(tostring(wide), tostring(tall), tostring(roomWide), tostring(roomTall)))
	check(wide > 0 and tall > 0, "the logs came out at no size at all")
	check(Window.Count("party") == e,
		"a whisper was filed in the party room as well")

	-- The one you send, which the client reports with the recipient in the
	-- sender's place. It belongs in the conversation with that person, because
	-- half a conversation is not one.
	fire("CHAT_MSG_WHISPER_INFORM", "on my way", "Aria")
	check(Window.Count(whisper) == 2, "a whisper you sent did not reach that conversation")

	-- The numbered channels are a setting and it ships off. They have no room of
	-- their own either way: they are the volume the window exists to get away
	-- from, and Conversation is where they land when they are wanted at all.
	local j = held()
	fire("CHAT_MSG_CHANNEL", "wts", "Spammer", nil, "1. General", nil, nil, 1, "General")
	check(held() == j, "a numbered channel was captured with the setting off")

	ns.db.chatChannels = true
	Feed.Apply()
	fire("CHAT_MSG_CHANNEL", "wts", "Spammer", nil, "1. General", nil, nil, 1, "General")
	check(held() == j + 1, "a numbered channel was not captured with the setting on")
	ns.db.chatChannels = false
	Feed.Apply()
end

----------------------------------------------------------------------
-- What is unread
--
-- The count against a room's name is the whole alert design. It is kept while
-- the window is closed, because a count that was only kept while you were
-- watching would say nothing about the hour you were not.
----------------------------------------------------------------------

do
	Window.Go(Rooms.ALL)
	local before = Rooms.Unread("party")
	fire("CHAT_MSG_PARTY", "anyone", "Bram", nil, nil, nil, nil, nil, nil, nil, nil, nil, "P1")
	check(Rooms.Unread("party") == before + 1,
		"a line in a room you were not reading was not counted")
	check(Rooms.Unread(Rooms.ALL) == 0,
		"the room you are reading counted its own line as unread")

	Window.Go("party")
	check(Rooms.Unread("party") == 0, "reading a room did not clear its count")
end

----------------------------------------------------------------------
-- The eight most recent conversations
--
-- A room per person you are talking to, and no more of them than fit in a rail
-- you can read. The ninth pushes the least recent off, and everything anybody
-- said is still in Conversation.
----------------------------------------------------------------------

do
	local first = Rooms.WhisperId("Aria")
	for index = 1, 8 do
		fire("CHAT_MSG_WHISPER", "hello", "Stranger" .. index,
			nil, nil, nil, nil, nil, nil, nil, nil, nil, "S" .. index)
	end
	check(not Rooms.Exists(first),
		"a ninth conversation did not push the least recent one off the rail")
	check(Rooms.Exists(Rooms.WhisperId("Stranger8")), "the newest conversation is not there")
	check(Window.Count(first) == 0, "a conversation that fell off the rail kept its log")

	-- And the log it was using is given to the next one rather than left behind.
	local recycled = Window.Held()
	fire("CHAT_MSG_WHISPER", "hello", "Aria", nil, nil, nil, nil, nil, nil, nil, nil, nil, "P2")
	check(Window.Held() == recycled + 2,
		"a new conversation did not reuse the log the old one gave back")
end

----------------------------------------------------------------------
-- Blizzard's window, off the screen and back
----------------------------------------------------------------------

do
	-- Hidden at login, because that is the default. The part exists to replace
	-- that window and shipping beside it would be half a replacement.
	check(ns.ChatBlizzard.Hiding(), "the client's chat window is still on screen at login")
	check(not _G.ChatFrame1:IsShown(), "the first chat frame is still shown")
	check(not _G.ChatFrame2Tab:IsShown(), "a chat frame's tab is still shown")
	check(not _G.ChatFrameMenuButton:IsShown(), "the chat menu button is still shown")

	-- The client shows one again on its own, which is what ns.Strip is for: it
	-- puts the frame's own Hide where its Show was. Without it the window comes
	-- back the first time anything docks a frame or flashes a tab.
	_G.ChatFrame1:Show()
	check(not _G.ChatFrame1:IsShown(),
		"the client showed a chat frame again and nothing pushed it back down")

	-- Everything that would have been drawn there is drawn here instead. It is
	-- the only way a hidden window is not a deletion.
	--
	-- hooksecurefunc is installed for this block alone and taken away after,
	-- the same as in 39-party-raid.lua and for the same reason: leaving it in
	-- the fixture would switch on two hooks UnitFrames/Skin.lua has never been
	-- able to install here, which changes what every section above is
	-- measuring. Chat/Blizzard.lua asks for it again on every apply rather than
	-- once, which is what makes installing it this late work at all.
	_G.hooksecurefunc = function(target, name, post)
		local original = target[name]
		target[name] = function(...)
			original(...)
			post(...)
		end
	end
	ns.ChatBlizzard.Apply()
	_G.hooksecurefunc = nil

	local system = Window.Count(Rooms.SYSTEM)
	_G.DEFAULT_CHAT_FRAME:AddMessage("You receive loot: [Thunderfury]", 1, 1, 1)
	check(Window.Count(Rooms.SYSTEM) == system + 1,
		"a line Blizzard's window would have drawn reached nothing at all")
	check(Rooms.Exists(Rooms.SYSTEM), "there is no System room to read it in")
	check(ns.ChatBlizzard.Describe():find("hidden") ~= nil,
		("the hide reads %q"):format(ns.ChatBlizzard.Describe()))

	-- Hiding forces the claim, or every conversation line would be drawn twice:
	-- once here and once in a frame nobody can see.
	ns.db.chatClaim = false
	Feed.Apply()
	check(#(chat.filters.CHAT_MSG_PARTY or {}) == 1,
		"the claim came off while Blizzard's window was hidden, so the conversation is drawn twice")
	ns.db.chatClaim = true
	Feed.Apply()

	-- And a closed window puts the client's back, because a game with neither
	-- has no chat at all.
	Window.Hide()
	check(_G.ChatFrame1:IsShown(),
		"our window closed and the client's stayed hidden, so there is nowhere to read anything")
	Window.Show()
	check(not _G.ChatFrame1:IsShown(), "opening ours again did not take the client's back off")

	-- Read what is in it, then put the client's window back. A room that is
	-- neither live nor holding anything unread is a row in the rail saying
	-- nothing, so it goes; until it is read it stays, which is what keeps a line
	-- that arrived on the way out reachable.
	Window.Go(Rooms.SYSTEM)
	ns.db.hideBlizzChat = false
	Window.Apply()
	check(_G.ChatFrame1:IsShown(), "turning the setting off left the client's window hidden")
	check(_G.ChatFrame1Tab:IsShown(), "turning the setting off left a tab hidden")
	check(not Rooms.Exists(Rooms.SYSTEM),
		"the System room is still offered with Blizzard's window back on screen")
	check(Window.Room() == Rooms.ALL,
		("the room the window was in went away and it landed in %s")
			:format(tostring(Window.Room())))
end

----------------------------------------------------------------------
-- The claim
----------------------------------------------------------------------

do
	local function claimed(event)
		return #(chat.filters[event] or {})
	end

	check(claimed("CHAT_MSG_PARTY") == 1,
		("%d filters on party chat, expected exactly one"):format(claimed("CHAT_MSG_PARTY")))
	check(claimed("CHAT_MSG_CHANNEL") == 0,
		"the numbered channels are filtered out of Blizzard's window while they are not captured")
	check(chat.filters.CHAT_MSG_PARTY[1]() == true,
		"the filter let the message through, so both windows would draw it")

	-- Twice on and once off. The filter is looked up by identity when it is
	-- removed, so a fresh closure per apply would leave every earlier one in
	-- FrameXML's list forever.
	Feed.Apply()
	Feed.Apply()
	check(claimed("CHAT_MSG_PARTY") == 1,
		("applying three times left %d filters on party chat"):format(claimed("CHAT_MSG_PARTY")))

	ns.db.chatClaim = false
	Feed.Apply()
	check(claimed("CHAT_MSG_PARTY") == 0,
		"turning the claim off left Blizzard's window still filtered")
	ns.db.chatClaim = true
	Feed.Apply()
	check(claimed("CHAT_MSG_PARTY") == 1, "turning the claim back on did not filter again")

	-- The part off is the part gone: no events, no filters.
	ns.db.chat = false
	Feed.Apply()
	check(claimed("CHAT_MSG_PARTY") == 0, "the part is off and Blizzard's window is still filtered")
	local quiet = Window.Count(Rooms.ALL)
	fire("CHAT_MSG_PARTY", "anyone there", "Bram", nil, nil, nil, nil, nil, nil, nil, nil, nil, "P1")
	check(Window.Count(Rooms.ALL) == quiet, "a line was captured with the part switched off")
	ns.db.chat = true
	Feed.Apply()

	----------------------------------------------------------------------
	-- The claim follows the window
	--
	-- The filter takes a line out of Blizzard's frames on the promise that this
	-- window draws it instead. A closed window keeps no such promise, and the
	-- first version of this part held the filter anyway: one press of the close
	-- box deleted every say, party, guild, raid and whisper line from the
	-- screen, the closed state is saved, and the filters went back on at the
	-- next login. The only symptom was a chat log that had gone quiet, on both
	-- windows at once.
	----------------------------------------------------------------------

	-- Captured while it is installed, so it can be asked what it does once the
	-- reason for it has gone. The install is an optimisation; the filter
	-- deciding for itself is what makes a missed reapply cost a wasted call
	-- instead of the conversation.
	local stale = chat.filters.CHAT_MSG_PARTY[1]
	check(stale() == true,
		"the filter handed a line back to Blizzard's window while ours was open")

	Window.Hide()
	check(stale() == false,
		"a filter left behind after the window closed still deleted the line")
	check(claimed("CHAT_MSG_WHISPER_INFORM") == 0,
		"the window is closed and Blizzard's frames are still filtered, so the conversation is drawn nowhere")

	-- Still captured, because the log behind a closed window is the scrollback
	-- you read when you open it again.
	local dark = Window.Count(Rooms.ALL)
	fire("CHAT_MSG_WHISPER_INFORM", "on my way", "Aria")
	check(Window.Count(Rooms.ALL) == dark + 1,
		"a whisper sent while the window was closed did not reach the log behind it")

	Window.Show()
	check(claimed("CHAT_MSG_WHISPER_INFORM") == 1,
		"opening the window again did not take the conversation back off Blizzard's frames")
end

----------------------------------------------------------------------
-- Typing in it
--
-- The room you are reading is the channel you are typing into. There is no
-- second piece of state holding that, which is the whole redesign, so every
-- assertion here reads either the text in the field or what was sent.
----------------------------------------------------------------------

do
	local sent = #chat.sent
	Window.Go(Rooms.ALL)
	Window.Send("hello")
	check(#chat.sent == sent + 1, "a plain line was not sent at all")
	check(chat.sent[#chat.sent].kind == "SAY",
		("a plain line from Conversation went to %s, expected SAY")
			:format(tostring(chat.sent[#chat.sent].kind)))

	-- The same words in another room go somewhere else, and nothing was pressed
	-- in between but the room.
	Window.Go("party")
	Window.Send("hello")
	check(chat.sent[#chat.sent].kind == "PARTY",
		("a plain line from the party room went to %s")
			:format(tostring(chat.sent[#chat.sent].kind)))

	-- And the field says so before you type a word.
	Window.Focus()
	check(Window.Line() == "/p ",
		("the party room filled the line in with %q, expected \"/p \"")
			:format(Window.Line()))
	check(Compose.Note(Rooms.Target("party")) == "enter types /p",
		("the note above the log reads %q"):format(Compose.Note(Rooms.Target("party"))))

	-- /raid rather than /r, which is reply. Getting that the wrong way round
	-- sends a whisper meant for one person to forty.
	group.Set(PARTY, true)
	fire("GROUP_ROSTER_UPDATE")
	Window.Go("raid")
	Window.Focus()
	check(Window.Line() == "/raid ",
		("the raid room filled the line in with %q"):format(Window.Line()))

	-- The line you type in is drawn only while the cursor is in it. Not drawn
	-- means no fill and no hairline, so what is behind it is the window's own
	-- background at the player's own opacity, which is the same surface every
	-- line of the conversation sits on.
	--
	-- The focus is dropped through the edit box itself rather than through a
	-- method on the window, because the window has no reason to grow one: every
	-- way out of the field in the game is the client taking the focus away.
	local field = Window.Field()
	local line = field:GetChildren()
	Window.Focus()
	check(field.bg:IsShown(), "the line is not drawn with the cursor in it")
	check(field.edges[1]:IsShown(), "the line has no hairline with the cursor in it")
	line:ClearFocus()
	check(not field.bg:IsShown(),
		"the line is still painted over the window with the cursor out of it")
	check(not field.edges[1]:IsShown(),
		"the line's hairline is still drawn with the cursor out of it")

	-- The slash key. It is the second of the client's two chat keys and it was
	-- the one this window did not take, so pressing it opened Blizzard's
	-- invisible line and every slash command in the game went nowhere.
	--
	-- Bound off the client's own binding set rather than off the character "/",
	-- and read back through GetBindingAction, because a client that takes
	-- SetOverrideBindingClick and does nothing with it leaves no other trace.
	local hidBlizz = ns.db.hideBlizzChat
	ns.db.hideBlizzChat = true
	Window.Keys()
	check(_G.GetBindingAction("/", true) == "CLICK WarriorKitChatSlashButton:LeftButton",
		("the slash key runs %q with Blizzard's window hidden")
			:format(_G.GetBindingAction("/", true)))
	check(_G.GetBindingAction("ENTER", true) == "CLICK WarriorKitChatEnterButton:LeftButton",
		("the enter key runs %q with Blizzard's window hidden")
			:format(_G.GetBindingAction("ENTER", true)))

	-- And what it opens is a line with a slash in it and no room prefix. The
	-- prefix would turn every slash command into a sentence said out loud.
	Window.Go("party")
	Window.Slash()
	check(Window.Line() == "/",
		("the slash key opened the line with %q, expected \"/\""):format(Window.Line()))

	-- Both keys handed back the moment Blizzard's window is on screen again,
	-- because with that window up its own line works and there is nothing to fix.
	ns.db.hideBlizzChat = false
	Window.Keys()
	check(_G.GetBindingAction("/", true) == "",
		("the slash key is still held as %q with Blizzard's window up")
			:format(_G.GetBindingAction("/", true)))
	ns.db.hideBlizzChat = hidBlizz
	Window.Keys()

	-- A slash the player typed beats the room, because the text in the field is
	-- the only thing deciding where the line goes.
	Window.Send("/g anyone on")
	check(chat.sent[#chat.sent].kind == "GUILD",
		("/g from the raid room went to %s"):format(tostring(chat.sent[#chat.sent].kind)))
	check(chat.sent[#chat.sent].text == "anyone on",
		("the prefix was sent as part of the message: %q")
			:format(tostring(chat.sent[#chat.sent].text)))

	Window.Send("/w Aria on my way")
	check(chat.sent[#chat.sent].kind == "WHISPER" and chat.sent[#chat.sent].target == "Aria",
		"a whisper typed by hand did not reach the person named")

	-- /r answers whoever spoke last, which is the addon's own answer: the
	-- client keeps one and will not hand it out.
	Window.Send("/r still here")
	check(chat.sent[#chat.sent].target == "Aria",
		("/r went to %s"):format(tostring(chat.sent[#chat.sent].target)))

	-- A prefix with nothing after it is the field as the window filled it in
	-- and enter pressed twice. An empty line in front of forty people is worse
	-- than nothing happening.
	local quiet = #chat.sent
	Window.Send("/p ")
	check(#chat.sent == quiet, "a prefix with no message behind it was sent anyway")

	-- A slash the addon does not know is the client's business, from /dance to
	-- another addon's command.
	local ran = #chat.slash
	Window.Send("/dance")
	check(#chat.slash == ran + 1 and chat.slash[#chat.slash] == "/dance",
		"a slash command was not handed to the client's own parser")
	check(#chat.sent == quiet, "a slash command was also sent as a chat message")

	-- Tab steps to the next room and rewrites the slash in front of the cursor,
	-- which is the same key that cycled the channel in the window this replaced
	-- and means the same thing.
	Window.Go("say")
	Window.Focus()
	check(Window.Line() == "/s ", ("the say room filled in %q"):format(Window.Line()))
	Window.Step(1)
	check(Window.Room() ~= "say", "tab did not move to another room")
	check(Window.Line() ~= "/s ", "tab moved room and left the old slash in the line")

	-- Clicking a name answers it: their own room, and their name in the field.
	Window.Reply("Bram")
	check(Window.Room() == Rooms.WhisperId("Bram"),
		("answering a name landed in %s"):format(tostring(Window.Room())))
	check(Window.Line() == "/w Bram ",
		("answering a name filled in %q"):format(Window.Line()))
	Window.Send("on my way")
	check(chat.sent[#chat.sent].kind == "WHISPER" and chat.sent[#chat.sent].target == "Bram",
		"the reply did not go to the person whose name was clicked")

	-- A group is people rather than a channel, so enter answers whoever last
	-- spoke there and says so above the log rather than leaving you to find out
	-- by sending.
	Window.Go(family)
	Window.Focus()
	check(Window.Line() == "/w Aria " or Window.Line() == "/w Bram ",
		("a group room filled in %q, expected a whisper to whoever spoke last")
			:format(Window.Line()))

	-- One tick and the field is empty again, for somebody who types /p by hand.
	ns.db.chatPrefix = false
	Window.Go("party")
	Window.Focus()
	check(Window.Line() == "/w Aria " or Window.Line() == "/w Bram ",
		"turning the prefix off rewrote a line that was already there")
	ns.db.chatPrefix = true
end

----------------------------------------------------------------------
-- Rooms that stop existing
--
-- Leaving the party has to move you somewhere rather than leave you typing into
-- a channel the server refuses.
----------------------------------------------------------------------

do
	Window.Go("party")
	group.Forget()
	fire("GROUP_ROSTER_UPDATE")
	check(Window.Room() ~= "party" or Rooms.Unread("party") > 0,
		"the party is gone and the window is still in the party room")
	check(select(1, Window.Channel()) ~= "PARTY",
		"the party is gone and a line would still be typed into party chat")

	group.Set(PARTY)
	fire("GROUP_ROSTER_UPDATE")
end

----------------------------------------------------------------------
-- The log, on a client that says no
----------------------------------------------------------------------

-- The insert mode, written and read back. This client takes only the lower
-- case spelling, which is one of the two the wiki records, and the log has
-- to find that out by reading rather than by assuming.
chat.insertStrict = "bottom"
local fussy = ns.UI.Log(_G.UIParent)
check(fussy ~= nil and fussy.bottomInsert,
	"the log gave up on a client that takes only one spelling of the insert mode")
chat.insertStrict = nil

-- And no message frame at all, which costs the log and says so rather than
-- raising inside the window that was being built.
local realCreate = _G.CreateFrame
_G.CreateFrame = function(kind, ...)
	if kind == "ScrollingMessageFrame" then
		error("this client has no ScrollingMessageFrame")
	end
	return realCreate(kind, ...)
end
local refused, reason = ns.UI.Log(_G.UIParent)
_G.CreateFrame = realCreate
check(refused == nil and type(reason) == "string",
	"a client with no message frame did not refuse the log cleanly")

----------------------------------------------------------------------

-- Put the scene back. Every section after this one walks the frames on the
-- grid, and a party left standing here is a party the next test did not ask
-- for.
group.Forget()

print(("chat   %d rooms, %d lines held, %d unread; %d filters; Blizzard's %s")
	:format(Window.Rooms(), Window.Held(), Rooms.Waiting(), Feed.Claimed(),
		ns.ChatBlizzard.Describe()))
