local ADDON, ns = ...

local Voice = {}
ns.Voice = Voice

--------------------------------------------------------------------------
-- Voice
--
-- One setting: which voice channel this character should be in. The addon puts
-- you in it at login and again whenever the channel it names comes into
-- existence, which for a party channel is the moment you group up.
--
-- **It only ever joins.** Nothing here leaves a channel, mutes anything, sets a
-- device or touches a volume. Those are the client's own settings, a player
-- pressed a button to get them where they are, and an addon that undid one
-- would be doing something nobody asked for while their hands were full. The
-- whole of this part is the press you would have made yourself.
--
-- **There are no custom voice channels to pick.** Blizzard's voice chat is not
-- the one from patch 2.2 that had channels you could name; since it was rebuilt
-- on the Battle.net service it is attached to the groups you are already in.
-- What that leaves to choose between is your party or raid, and a voice channel
-- belonging to a community, where this client has communities at all. So the
-- picker is short, and it is short because the game is, rather than because
-- this file is unfinished.
--
-- Everything below is probed. C_VoiceChat is on both clients this addon ships
-- for, and the enum beside it may not be, and nothing installed here proves any
-- single function in it, so each one is looked up by name before it is called
-- and a missing one costs the feature rather than raising.
--------------------------------------------------------------------------

-- The channel types, out of the client's own enum where it has one.
--
-- The numbers are the fallback and they are the values the enum has carried
-- since it was added: 0 none, 1 custom, 2 a private party, 3 a public one, 4 a
-- community. Custom is in the enum and is not offered, because nothing in these
-- clients makes one.
local function ChannelType(name, fallback)
	local enum = _G.Enum and _G.Enum.ChatChannelType
	if enum then
		-- The generated enum has spelled this field both ways across builds, so
		-- both are asked for before falling back to the number.
		local value = enum[name] or enum[name:gsub("_", "")]
		if type(value) == "number" then
			return value
		end
	end
	return fallback
end

-- The one type this file joins by type. A community channel is joined by the
-- club and stream behind it instead, because those two numbers survive a
-- logout and a channel type does not name which community you meant.
local PRIVATE_PARTY = ChannelType("Private_Party", 2)

-- The picker's own values. Strings rather than a table, because this is a saved
-- setting and a string survives a shape change in a way a table does not.
Voice.NONE = "none"
Voice.GROUP = "group"

-- How long between two attempts at the same thing. A join is a request to a
-- service rather than a local call, and the events that would make us retry
-- (a roster change, a channel appearing) arrive in bursts.
local RETRY = 3

-- How many times we ask before giving up until something changes. A channel
-- that will not come up is a channel the player has to sort out in the client's
-- own settings, and an addon asking forever is an addon spamming a service.
local ATTEMPTS = 5

local lastTry, tries = 0, 0
local lastResult = "nothing asked for yet"

--------------------------------------------------------------------------
-- What the client will answer
--------------------------------------------------------------------------

local function API(name)
	local api = _G.C_VoiceChat
	if not api then
		return nil
	end
	local fn = api[name]
	if type(fn) ~= "function" then
		return nil
	end
	return fn
end

-- Whether there is a voice service here at all, and why not when there is not.
function Voice.Supported()
	if not _G.C_VoiceChat then
		return false, "this client has no voice chat"
	end
	if not API("GetChannelForChannelType") or not API("ActivateChannel") then
		return false, "this client's voice chat has no channel API"
	end

	local enabled = API("IsEnabled")
	if enabled and enabled() == false then
		return false, "voice chat is switched off in the client's own settings"
	end
	return true
end

-- Whether the service says it has signed in.
--
-- Reported and never gated on, and that distinction cost a release. This used
-- to be a refusal at the top of Apply: a false answer meant "wait", and nothing
-- was tried until it turned true. On this client it does not turn true. It
-- reads false with the service plainly working, and pressing the voice button
-- in the client's own Chat Channels window joins the channel while this is
-- still saying no, so the addon sat there refusing to make the call that would
-- have worked at any point in the evening.
--
-- The rule this file broke is the one the rest of the addon holds to: probe
-- what you are about to call, not the weather around it. Whether a join lands
-- is answered by making the join. A precondition invented on top of that is a
-- feature that can only be more broken than the API under it.
function Voice.Ready()
	local loggedIn = API("IsLoggedIn")
	if not loggedIn then
		return nil
	end
	return loggedIn() and true or false
end

-- Sign the voice client in, where it says it is not and the client has the
-- call. Blizzard's own interface does this on your behalf when you reach for
-- voice, which is what pressing the circle in Chat Channels is doing, so the
-- addon asks for the same thing before it asks for a channel.
--
-- Rate limited with the join below rather than separately, because it is the
-- same kind of request to the same service and this is not something to ask for
-- twice a second.
local function SignIn()
	if Voice.Ready() ~= false then
		return false
	end
	local login = API("Login")
	if not login then
		return false
	end
	pcall(login)
	return true
end

--------------------------------------------------------------------------
-- What can be picked
--------------------------------------------------------------------------

-- A community voice channel is named by the club and the stream it belongs to,
-- and both of those numbers survive a logout, which is why the setting holds
-- them rather than the channelID. A channelID is handed out per session and
-- saving one would mean joining whatever happened to take that number
-- tomorrow.
local function ClubKey(clubId, streamId)
	return ("club:%s:%s"):format(tostring(clubId), tostring(streamId))
end

local function ParseClub(value)
	local clubId, streamId = value:match("^club:(.-):(.+)$")
	if not clubId then
		return nil
	end
	return clubId, streamId
end

-- Every stream of every community you are in, whether or not there is a voice
-- channel behind it yet.
--
-- This listed only the streams the client already had a channel for at first,
-- on the argument that a text stream is not a voice channel and offering one
-- that is not there would be a lie. That was wrong, and the client's own Chat
-- Channels window is the proof: it draws a voice button on every community
-- stream, because a community voice channel does not exist until somebody joins
-- it and pressing that button is what makes it. A channel that exists is the
-- state after the first person arrives, not a property of the stream.
--
-- Listing only the existing ones therefore emptied the picker at exactly the
-- moment it is used. You pick a channel to join at login, and at login you have
-- joined nothing, so the community you meant was never on the list.
--
-- The pick is keyed by the club and the stream, and both of those numbers
-- survive a logout. A channelID does not: it is handed out per session, so
-- saving one would mean joining whatever happens to take that number tomorrow.
local function Clubs()
	local rows = {}
	local club = _G.C_Club
	if not club
		or type(club.GetSubscribedClubs) ~= "function"
		or type(club.GetStreams) ~= "function" then
		return rows
	end

	local ok, subscribed = pcall(club.GetSubscribedClubs)
	if not ok or type(subscribed) ~= "table" then
		return rows
	end

	for _, info in ipairs(subscribed) do
		local streamsOk, streams = pcall(club.GetStreams, info.clubId)
		if streamsOk and type(streams) == "table" then
			for _, stream in ipairs(streams) do
				rows[#rows + 1] = {
					value = ClubKey(info.clubId, stream.streamId),
					text = ("%s: %s"):format(info.name or "community",
						stream.name or "voice"),
				}
			end
		end
	end
	return rows
end

-- What the picker offers, newest state each time it is opened, the way every
-- picker in this addon works.
function Voice.Options()
	local rows = {
		{ value = Voice.NONE, text = "|cff909090do not join anything|r" },
		{ value = Voice.GROUP, text = "your party or raid" },
	}
	for _, row in ipairs(Clubs()) do
		rows[#rows + 1] = row
	end

	-- The pick has to be in the list even when the client cannot see it today,
	-- or opening the picker would look like nothing is chosen and one click
	-- anywhere would throw the setting away. Communities load a few seconds
	-- after you enter the world, so this row is what is showing for those few
	-- seconds on every login.
	local chosen = ns.db.voiceJoin
	for _, row in ipairs(rows) do
		if row.value == chosen then
			return rows
		end
	end
	rows[#rows + 1] = {
		value = chosen,
		text = ("%s |cff808080(not loaded yet)|r"):format(Voice.Remembered()),
	}
	return rows
end

-- What the pick was called when you made it.
--
-- Saved beside the pick itself, because the name lives in the club list and the
-- club list is not there at login. Without it the picker and the status line
-- read "club:1234:5" for the first few seconds of every session, which is the
-- setting spelled in a language nobody chose it in.
function Voice.Remembered()
	local saved = ns.db.voiceLabel
	if type(saved) == "string" and saved ~= "" then
		return saved
	end
	return ns.db.voiceJoin
end

function Voice.Label(value)
	value = value or ns.db.voiceJoin
	if value == Voice.NONE then
		return "nothing"
	end
	if value == Voice.GROUP then
		return "your party or raid"
	end
	for _, row in ipairs(Clubs()) do
		if row.value == value then
			return row.text
		end
	end
	if value == ns.db.voiceJoin then
		return Voice.Remembered()
	end
	return value
end

--------------------------------------------------------------------------
-- Being in one
--------------------------------------------------------------------------

-- The channel the setting names, if the client has one right now.
local function Target()
	local value = ns.db.voiceJoin
	if value == Voice.NONE then
		return nil
	end

	if value == Voice.GROUP then
		local forType = API("GetChannelForChannelType")
		return forType and forType(PRIVATE_PARTY) or nil, "type", PRIVATE_PARTY
	end

	local clubId, streamId = ParseClub(value)
	if not clubId then
		return nil
	end
	local forStream = API("GetChannelForCommunityStream")
	if not forStream then
		return nil, "club", clubId, streamId
	end
	local ok, channel = pcall(forStream, tonumber(clubId) or clubId, tonumber(streamId) or streamId)
	return (ok and channel) or nil, "club", clubId, streamId
end

-- The channel this character is talking in right now, whatever put them there.
function Voice.Active()
	local activeId = API("GetActiveChannelID")
	local get = API("GetChannel")
	if not activeId or not get then
		return nil
	end
	local id = activeId()
	if not id then
		return nil
	end
	local ok, channel = pcall(get, id)
	return ok and channel or nil
end

--------------------------------------------------------------------------
-- Joining
--
-- Three states and one call each. The channel exists and we are in it, in which
-- case there is nothing to do; it exists and we are not, which is one
-- activation; or it does not exist yet, which is a request to the service and
-- an event later.
--
-- force is what the panel's button and the slash word pass. It clears the
-- attempt count, because a player pressing "join now" has said the situation
-- changed whatever this file thinks.
--------------------------------------------------------------------------

function Voice.Apply(force)
	if ns.db.voiceJoin == Voice.NONE then
		lastResult = "nothing picked"
		return false, lastResult
	end

	local ok, why = Voice.Supported()
	if not ok then
		lastResult = why
		return false, lastResult
	end
	if force then
		tries = 0
	end

	local channel, kind, first, second = Target()
	if channel then
		if channel.isActive then
			tries = 0
			lastResult = "already in " .. (channel.name or "it")
			return true, lastResult
		end
		local activate = API("ActivateChannel")
		if not activate then
			lastResult = "this client cannot activate a channel"
			return false, lastResult
		end
		activate(channel.channelID)
		tries = 0
		lastResult = "joined " .. (channel.name or "it")
		return true, lastResult
	end

	-- Nothing to activate, so the channel has to be asked for. This is the path
	-- that is rate limited: the events that lead here arrive in bursts and each
	-- one of these is a request to a service.
	local now = GetTime and GetTime() or 0
	if tries >= ATTEMPTS then
		lastResult = "gave up asking for " .. Voice.Label()
		return false, lastResult
	end
	if now - lastTry < RETRY then
		return false, lastResult
	end
	lastTry, tries = now, tries + 1
	SignIn()

	-- A setting holding something neither branch below understands, which is a
	-- saved variable edited by hand or a shape this file used to write.
	if kind ~= "type" and kind ~= "club" then
		lastResult = "the saved pick is not a channel this addon knows"
		return false, lastResult
	end

	if kind == "type" then
		local request = API("RequestJoinChannelByChannelType")
		if not request then
			lastResult = "this client cannot ask to join by channel type"
			return false, lastResult
		end
		request(first, true)
		lastResult = "asked for the group channel"
		return true, lastResult
	end

	local request = API("RequestJoinAndActivateCommunityStreamChannel")
	if not request then
		lastResult = "this client cannot ask to join a community channel"
		return false, lastResult
	end
	request(tonumber(first) or first, tonumber(second) or second)
	lastResult = "asked for " .. Voice.Label()
	return true, lastResult
end

-- The setting changed, so whatever this file had given up on is worth trying
-- again.
function Voice.Set(value)
	ns.db.voiceJoin = value
	-- What the row that was just clicked was called, saved beside the pick. The
	-- club list is in front of us at exactly this moment and not at the login
	-- where the name is wanted, so it is read here rather than looked up there.
	if value == Voice.NONE or value == Voice.GROUP then
		ns.db.voiceLabel = ""
	else
		for _, row in ipairs(Clubs()) do
			if row.value == value then
				ns.db.voiceLabel = row.text
			end
		end
	end
	tries, lastTry = 0, 0
	if value == Voice.NONE then
		lastResult = "nothing picked"
		return
	end
	Voice.Apply(true)
end

function Voice.Describe()
	if ns.db.voiceJoin == Voice.NONE then
		return "not joining anything"
	end
	local ok, why = Voice.Supported()
	if not ok then
		return why
	end
	local channel = Voice.Active()
	if channel then
		return ("in %s, set to join %s"):format(channel.name or "a channel", Voice.Label())
	end
	return ("set to join %s (%s)"):format(Voice.Label(), lastResult)
end

-- Every answer the client gives about voice, in one line.
--
-- Here because the first thing that went wrong with this part was invisible
-- from the game: the addon said it was waiting for a service that was already
-- working, and there was no way to ask which of the four probes behind that
-- sentence had produced it. A part that talks to a service it cannot see has to
-- be able to say what the service said.
function Voice.Diagnose()
	if not _G.C_VoiceChat then
		return "no C_VoiceChat on this client"
	end

	local enabled = API("IsEnabled")
	local ready = Voice.Ready()
	local channel = Target()
	local active = Voice.Active()

	return ("enabled %s, signed in %s, channel %s, active %s, %d of %d tries, last %s")
		:format(enabled and tostring(enabled()) or "not asked",
			ready == nil and "not asked" or tostring(ready),
			channel and (channel.name or "yes") or "none yet",
			active and (active.name or "yes") or "none",
			tries, ATTEMPTS, lastResult)
end

--------------------------------------------------------------------------
-- When to try
--
-- Every one of these is a moment the answer could have changed: entering the
-- world, the group changing under you, the service signing in, and a channel
-- appearing or being taken away. There is no ticker: a channel that never turns
-- up is a channel nothing is waiting for.
--------------------------------------------------------------------------

local EVENTS = {
	"PLAYER_ENTERING_WORLD",
	"GROUP_ROSTER_UPDATE",
	"VOICE_CHAT_LOGIN",
	"VOICE_CHAT_CONNECTION_SUCCESS",
	"VOICE_CHAT_CHANNEL_JOINED",
	"VOICE_CHAT_CHANNEL_ACTIVATED",
	"VOICE_CHAT_CHANNEL_REMOVED",
	"CLUB_STREAMS_LOADED",
}

local frame = CreateFrame("Frame")
for _, event in ipairs(EVENTS) do
	-- An event a client does not know raises rather than answering, and this
	-- list spans two of them.
	pcall(frame.RegisterEvent, frame, event)
end

frame:SetScript("OnEvent", function(_, event)
	if not ns.db then
		return
	end
	if event == "VOICE_CHAT_CHANNEL_ACTIVATED" then
		-- Somebody or something got us into a channel, which is the end state
		-- this file exists to reach. Nothing to do but stop counting.
		tries = 0
		return
	end
	-- The service arriving is new information, so whatever this file had given
	-- up on before it arrived is worth trying again from a clean count.
	if event == "VOICE_CHAT_LOGIN" or event == "VOICE_CHAT_CONNECTION_SUCCESS" then
		tries, lastTry = 0, 0
	end
	Voice.Apply()
end)
