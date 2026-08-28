-- Voice
--
-- One question, and it is not about chat. The rooms, the routing and the log
-- are Chat/, and this is a Battle.net service the addon asks for a channel:
-- does the pick ask exactly once for a channel that is not there, and activate
-- rather than ask for one that is.
--
-- That is worth its own section because the events driving it arrive in bursts.
-- GROUP_ROSTER_UPDATE fires several times for one person joining, and a join
-- request per event is an addon hammering somebody else's service. Every check
-- below is a count of the calls the stub service actually received.
--
-- It was the tail of 29-social.lua until that file went past the eight hundred
-- line budget. Splitting it out is what the budget is for, and this is the seam
-- it was always going to come apart on: nothing here reads a room, a line or a
-- window, and nothing there reads a voice channel.

local H = ...
local chat, advance = H.chat, H.advance
local ns, fire, check = H.ns, H.fire, H.check

local Voice = ns.Voice

-- The voice button. Two things, and both of them are the button's whole job.
--
-- It opens the client's own Chat Channels window, because that is where the
-- voice roster and the per person volume are and this addon draws neither.
-- ChatFrameChannelButton is on Chat/Blizzard.lua's furniture list, so with the
-- client's chat frame hidden this is the only way back to them.
local opened = chat.voice.channelWindow or 0
check(ns.ChatWindow.Voice(),
	"the voice button refused to open the client's Chat Channels window")
check((chat.voice.channelWindow or 0) == opened + 1,
	"the voice button did not reach the client's Chat Channels window")

-- And it says whether you are connected, which is the one fact about voice that
-- was nowhere on the screen. Green in a channel and quiet out of one, read off
-- the button's own text colour rather than off a flag this file could set.
local function mic()
	local r, g, b = ns.ChatWindow.Mic():GetTextColor()
	return ("%.2f %.2f %.2f"):format(r, g, b)
end
local C = ns.UI.Color
local function said(color)
	return ("%.2f %.2f %.2f"):format(color[1], color[2], color[3])
end

chat.voice.active = nil
ns.Voice.OnChange()
check(mic() == said(C.quiet),
	("the microphone is %s with no voice channel active, expected the quiet grey")
		:format(mic()))

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

-- And now the microphone at the foot of the chat rail is lit, which is the
-- whole of what a player sees about any of this. The activate above went
-- through the client's own event, so this is the real path rather than a
-- repaint called by hand.
check(mic() == said(ns.UI.Color.tick),
	("the microphone is %s in a live voice channel, expected the lit green")
		:format(mic()))

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

print(("voice  %s"):format(Voice.Describe()))
