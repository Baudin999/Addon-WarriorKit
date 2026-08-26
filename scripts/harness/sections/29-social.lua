-- The social part
--
-- Four questions no amount of reading Chat/ will answer.
--
-- Does a line reach the tabs it belongs on, and only those. The whole feature
-- is a routing decision made once per message, and the two ways it can be
-- wrong, everything on one tab and nothing on the people tab, look identical
-- in the source and identical on a screenshot of an empty window.
--
-- Does the claim on Blizzard's frames come back off. It is a filter added to a
-- FrameXML list, and a filter that is added twice or never removed is a chat
-- window that goes quiet and stays quiet until a reload.
--
-- Does the voice pick ask the service exactly once for a channel that is not
-- there, and activate rather than ask for one that is. The events that drive it
-- arrive in bursts, and a join request per event is an addon hammering a
-- Battle.net service.
--
-- And does a client that refuses a ScrollingMessageFrame, or refuses one of the
-- two spellings of its insert mode, cost the log rather than the window.

local H = ...
local chat, guids, unitClass = H.chat, H.guids, H.unitClass
local unitName, realPlayers, advance = H.unitName, H.realPlayers, H.advance
local ns, fire, check = H.ns, H.fire, H.check

local Feed, People, Window, Voice = ns.ChatFeed, ns.People, ns.ChatWindow, ns.Voice

check(_G.WarriorKitChat ~= nil, "no chat window was built at login")
check(Window.Built(), "the chat window says it was not built")
check(_G.WarriorKitChat:GetWidth() == ns.db.chatWidth,
	("the chat window is %s wide and the setting says %s")
		:format(tostring(_G.WarriorKitChat:GetWidth()), tostring(ns.db.chatWidth)))

----------------------------------------------------------------------
-- The people list
----------------------------------------------------------------------

check(People.Count() == 0, "the people list did not ship empty")
check(Window.Tabs() == 2,
	("%d tabs with nobody on the list, expected the people tab not to be drawn")
		:format(Window.Tabs()))

check(People.Add("Aria") == 1, "the first name did not go on the list")
Window.Apply()
check(Window.Tabs() == 3,
	("%d tabs with somebody on the list, expected the people tab to appear")
		:format(Window.Tabs()))
check(People.Match("aria") ~= nil, "a name matched only in the case it was typed")
check(People.Match("Aria-Firemaw") ~= nil, "a realm suffix stopped a name matching")
check(People.Match("Ariax") == nil, "a name that is not on the list matched anyway")
check(People.Add("ARIA-Nethergarde") == nil,
	"the same person went on the list twice under a different realm")

-- Everyone with you, in one press. Three party tokens, one of them already
-- on the list, because the button has to be pressable twice.
chat.groupSize = 3
guids.party1, unitName.party1, unitClass.party1 = "P1", "Bram", "WARRIOR"
guids.party2, unitName.party2, unitClass.party2 = "P2", "Aria", "PRIEST"
realPlayers.party1, realPlayers.party2 = true, true
local added, skipped = People.AddGroup()
check(added == 1 and skipped == 1,
	("adding the group added %d and skipped %d, expected one of each")
		:format(added, skipped))
check(People.Count() == 2, ("the list holds %d, expected 2"):format(People.Count()))

----------------------------------------------------------------------
-- Routing
--
-- Counted off the tabs themselves rather than off a sink installed for the
-- test, because what is being asserted is where a line landed and a test
-- sink would be asserting that the feed called the test sink.
----------------------------------------------------------------------

-- In a block of its own, so the two dozen names this needs stop existing
-- before the voice tests start. The budget is no longer the reason, since a
-- file is a chunk of its own now; reading is. Nothing below this block wants
-- to know what a chat line count was called inside it.
do
	local function held()
		return Window.Count(Feed.CHAT), Window.Count(Feed.WHISPER), Window.Count(Feed.PEOPLE)
	end

	local chatLines, whisperLines, peopleLines = held()
	fire("CHAT_MSG_PARTY", "pull it", "Stranger", nil, nil, nil, nil, nil, nil, nil, nil, nil, "GX")
	local a, b, c = held()
	check(a == chatLines + 1, "a party line from a stranger did not reach the chat tab")
	check(b == whisperLines, "a party line reached the whispers tab")
	check(c == peopleLines, "a party line from a stranger reached the people tab")

	fire("CHAT_MSG_PARTY", "coming", "Bram", nil, nil, nil, nil, nil, nil, nil, nil, nil, "P1")
	local d, e, f = held()
	check(d == a + 1, "a party line from somebody on the list missed the chat tab")
	check(f == c + 1, "a party line from somebody on the list missed the people tab")
	check(e == b, "a party line reached the whispers tab")

	fire("CHAT_MSG_WHISPER", "where are you", "Aria", nil, nil, nil, nil, nil, nil, nil, nil, nil, "P2")
	local g, h, i = held()
	check(g == d + 1 and h == e + 1 and i == f + 1,
		"a whisper from somebody on the list did not reach all three tabs")

	-- The one you send, which the client reports with the recipient in the
	-- sender's place. It belongs on the people tab because the conversation is
	-- with a person on the list, and half a conversation is not one.
	fire("CHAT_MSG_WHISPER_INFORM", "on my way", "Aria")
	local j, k, l = held()
	check(j == g + 1 and k == h + 1 and l == i + 1,
		"a whisper sent to somebody on the list did not reach all three tabs")

	-- The numbered channels are a setting and it ships off.
	fire("CHAT_MSG_CHANNEL", "wts", "Spammer", nil, "1. General", nil, nil, 1, "General")
	local m = held()
	check(m == j, "a numbered channel was captured with the setting off")

	ns.db.chatChannels = true
	Feed.Apply()
	fire("CHAT_MSG_CHANNEL", "wts", "Spammer", nil, "1. General", nil, nil, 1, "General")
	check(held() == j + 1, "a numbered channel was not captured with the setting on")
	ns.db.chatChannels = false
	Feed.Apply()

	----------------------------------------------------------------------
	-- The claim
	----------------------------------------------------------------------

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
	local quiet = held()
	fire("CHAT_MSG_PARTY", "anyone there", "Bram", nil, nil, nil, nil, nil, nil, nil, nil, nil, "P1")
	check(held() == quiet, "a line was captured with the part switched off")
	ns.db.chat = true
	Feed.Apply()

	----------------------------------------------------------------------
	-- The claim follows the window
	--
	-- The filter takes a line out of Blizzard's frames on the promise that
	-- this window draws it instead. A closed window keeps no such promise,
	-- and the first version of this part held the filter anyway: one press
	-- of the close box deleted every say, party, guild, raid and whisper
	-- line from the screen, the closed state is saved, and the filters went
	-- back on at the next login. The only symptom was a chat log that had
	-- gone quiet, on both windows at once.
	----------------------------------------------------------------------

	-- Captured while it is installed, so it can be asked what it does once
	-- the reason for it has gone. The install is an optimisation; the
	-- filter deciding for itself is what makes a missed reapply cost a
	-- wasted call instead of the conversation.
	local stale = chat.filters.CHAT_MSG_PARTY[1]
	check(stale() == true,
		"the filter handed a line back to Blizzard's window while ours was open")

	Window.Hide()
	check(stale() == false,
		"a filter left behind after the window closed still deleted the line")
	check(claimed("CHAT_MSG_WHISPER_INFORM") == 0,
		"the window is closed and Blizzard's frames are still filtered, so the conversation is drawn nowhere")
	check(claimed("CHAT_MSG_PARTY") == 0,
		"the window is closed and party chat is still taken out of Blizzard's frames")

	-- Still captured, because the log behind a closed window is the
	-- scrollback you read when you open it again.
	local dark = Window.Count(Feed.WHISPER)
	fire("CHAT_MSG_WHISPER_INFORM", "on my way", "Aria")
	check(Window.Count(Feed.WHISPER) == dark + 1,
		"a whisper sent while the window was closed did not reach the log behind it")

	Window.Show()
	check(claimed("CHAT_MSG_WHISPER_INFORM") == 1,
		"opening the window again did not take the conversation back off Blizzard's frames")
	check(claimed("CHAT_MSG_PARTY") == 1,
		"opening the window again left party chat drawing in both")

	----------------------------------------------------------------------
	-- What a line looks like
	----------------------------------------------------------------------

	chat.classByGuid.P1 = "WARRIOR"
	local before = Window.Count(Feed.CHAT)
	fire("CHAT_MSG_PARTY", "ready", "Bram", nil, nil, nil, nil, nil, nil, nil, nil, nil, "P1")
	check(Window.Count(Feed.CHAT) == before + 1, "the line with a GUID on it was dropped")

	----------------------------------------------------------------------
	-- Typing in it
	----------------------------------------------------------------------

	local sent = #chat.sent
	Window.Send("hello")
	check(#chat.sent == sent + 1, "a plain line was not sent at all")
	check(chat.sent[#chat.sent].kind == "SAY",
		("a plain line went to %s, expected SAY"):format(tostring(chat.sent[#chat.sent].kind)))

	-- A slash goes to the client's own parser rather than to a parser written
	-- here, because the client's is the one that knows every command in the game
	-- and every other addon's.
	local ran = #chat.slash
	Window.Send("/dance")
	check(#chat.slash == ran + 1 and chat.slash[#chat.slash] == "/dance",
		"a slash command was not handed to the client's own parser")
	check(#chat.sent == sent + 1, "a slash command was also sent as a chat message")

	-- Clicking a name answers it, which is a whisper to that name and nothing
	-- else.
	Window.Reply("Aria")
	local kind, target = Window.Channel()
	check(kind == "WHISPER" and target == "Aria",
		("answering a name typed into %s at %s"):format(tostring(kind), tostring(target)))
	Window.Send("on my way")
	check(chat.sent[#chat.sent].kind == "WHISPER" and chat.sent[#chat.sent].target == "Aria",
		"the reply did not go to the person whose name was clicked")

	-- Guild is offered while you are in one and skipped while you are not, so
	-- the cycle cannot land on a channel the server would refuse.
	chat.inGuild = false
	for _ = 1, #({ "say", "party", "raid", "guild", "yell", "reply" }) do
		Window.Cycle(1)
		check(select(1, Window.Channel()) ~= "GUILD",
			"the channel cycled onto guild chat with no guild")
	end

end

----------------------------------------------------------------------
-- Voice
----------------------------------------------------------------------

check(Voice.Supported(), "the stub voice service was not recognised")

local calls = #chat.voice.calls
Voice.Set(Voice.NONE)
check(#chat.voice.calls == calls, "the voice pick asked for a channel with nothing picked")

-- Nothing to activate, so exactly one request, and no second one until the
-- retry window has passed however many events arrive.
Voice.Set(Voice.GROUP)
check(#chat.voice.calls == calls + 1,
	("picking the group channel made %d calls, expected one")
		:format(#chat.voice.calls - calls))
check(chat.voice.calls[#chat.voice.calls].what == "requestType",
	"the group pick did not ask to join by channel type")
check(chat.voice.calls[#chat.voice.calls].autoActivate == true,
	"the join request did not ask for the channel to be activated")

local asked = #chat.voice.calls
fire("GROUP_ROSTER_UPDATE")
fire("GROUP_ROSTER_UPDATE")
check(#chat.voice.calls == asked,
	("two roster changes in a burst made %d more requests")
		:format(#chat.voice.calls - asked))

-- The service signing in is not a burst of the same news, it is new news,
-- and it clears the rate limit rather than waiting it out. Everything this
-- file gave up on before the service existed is worth one more ask the
-- moment it does.
fire("VOICE_CHAT_LOGIN")
check(#chat.voice.calls > asked, "the voice service signed in and nothing was asked for")

-- The channel turns up. Now there is something to activate, and asking the
-- service again would be the wrong call entirely.
chat.voice.channels[2] = { channelID = 7, name = "Party", isActive = false }
advance(10)
fire("VOICE_CHAT_CHANNEL_JOINED")
check(chat.voice.calls[#chat.voice.calls].what == "activate",
	"a channel that exists was requested again instead of activated")
check(chat.voice.calls[#chat.voice.calls].channelID == 7,
	"the wrong channel was activated")

-- Already in it, so nothing at all.
local settled = #chat.voice.calls
advance(10)
fire("GROUP_ROSTER_UPDATE")
check(#chat.voice.calls == settled, "a channel already active was joined again")
check(Voice.Describe():find("Party") ~= nil,
	("voice says %q with the party channel active"):format(Voice.Describe()))

-- The communities. Every stream is offered, not only the ones that already
-- have a voice channel, because a community channel is made when the first
-- person joins it and at login nobody has.
local options = Voice.Options()
local offered = {}
for _, row in ipairs(options) do
	offered[row.value] = row.text
end
check(offered["club:11:1"] == "C & F: General",
	("the picker offered %s for the first community stream")
		:format(tostring(offered["club:11:1"])))
check(offered["club:11:2"] ~= nil and offered["club:22:1"] ~= nil,
	("%d options offered, expected both clubs and all three streams"):format(#options))

-- Picking one asks for it by club and stream, which are the two numbers that
-- survive a logout.
advance(10)
Voice.Set("club:11:1")
local asked_club = chat.voice.calls[#chat.voice.calls]
check(asked_club.what == "requestClub" and asked_club.clubId == 11 and asked_club.streamId == 1,
	"picking a community channel did not ask for it by club and stream")

-- And the name it was picked under is kept, so a login that has not loaded
-- the communities yet still says what you chose rather than the numbers.
check(ns.db.voiceLabel == "C & F: General",
	("the pick was remembered as %q"):format(tostring(ns.db.voiceLabel)))
local clubs = _G.C_Club
_G.C_Club = nil
check(Voice.Label() == "C & F: General",
	("with the communities not loaded the pick reads as %q"):format(Voice.Label()))
_G.C_Club = clubs

-- The channel turns up once somebody is in it, and then it is activated
-- rather than asked for again.
chat.voice.channels["club:11:1"] = { channelID = 9, name = "C & F General", isActive = false }
advance(10)
fire("VOICE_CHAT_CHANNEL_JOINED")
check(chat.voice.calls[#chat.voice.calls].what == "activate"
	and chat.voice.calls[#chat.voice.calls].channelID == 9,
	"a community channel that exists was asked for again instead of activated")
chat.voice.channels["club:11:1"] = nil
chat.voice.active = nil
Voice.Set(Voice.GROUP)

-- A service that says it is not signed in is told to sign in, and the join
-- is asked for anyway.
--
-- This was a refusal at the top of Apply, and it was wrong on the only
-- client that matters: IsLoggedIn reads false there with voice plainly
-- working, and pressing the voice button in the client's own window joins
-- the channel while it is still saying no. Nothing was ever tried. The rule
-- it broke is the one the rest of the addon holds to, which is to probe what
-- you are about to call rather than the weather around it, so the assertion
-- is now that a false answer costs nothing.
chat.voice.loggedIn = false
chat.voice.channels[2] = nil
chat.voice.active = nil
advance(10)
local before_login = #chat.voice.calls
local ok, why = Voice.Apply(true)
check(ok, ("a join was refused because the service said it was not signed in: %s")
	:format(tostring(why)))

local sawLogin, sawRequest = false, false
for index = before_login + 1, #chat.voice.calls do
	local call = chat.voice.calls[index]
	sawLogin = sawLogin or call.what == "login"
	sawRequest = sawRequest or call.what == "requestType"
end
check(sawLogin, "the service said it was not signed in and was never asked to sign in")
check(sawRequest, "the channel was never asked for")

-- And the diagnostic says what each probe answered, because the sentence
-- this part prints is a decision made out of four of them and the first bug
-- in it was invisible without them.
check(Voice.Diagnose():find("signed in false") ~= nil,
	("the diagnostic reads %q"):format(Voice.Diagnose()))
chat.voice.loggedIn = true

-- Asking forever is not an option. Past the attempt cap the requests stop
-- until something changes.
for _ = 1, 20 do
	advance(10)
	Voice.Apply()
end
local capped = #chat.voice.calls
advance(10)
Voice.Apply()
check(#chat.voice.calls == capped, "the voice pick kept asking past its own cap")

Voice.Set(Voice.NONE)

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
chat.groupSize = 0
guids.party1, guids.party2 = nil, nil
unitName.party1, unitName.party2 = nil, nil
unitClass.party1, unitClass.party2 = nil, nil
realPlayers.party1, realPlayers.party2 = nil, nil

print(("chat   %d tabs, %d lines on chat, %d on whispers, %d on people; %d filters held; voice %s")
	:format(Window.Tabs(),
		Window.Count(Feed.CHAT), Window.Count(Feed.WHISPER), Window.Count(Feed.PEOPLE),
		Feed.Claimed(), Voice.Describe()))
