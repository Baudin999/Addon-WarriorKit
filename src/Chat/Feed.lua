local ADDON, ns = ...

local Feed = {}
ns.ChatFeed = Feed

--------------------------------------------------------------------------
-- What people said
--
-- Every line of conversation the client hands out, turned into one string with
-- a colour, and handed to whoever is drawing. This file knows nothing about
-- windows, tabs or fonts. It knows which events carry a person talking, what
-- one line of that reads like, and which of the three streams a line belongs
-- to.
--
-- **Two mechanisms, one job each, and they are not the same job.**
--
-- The capture is an ordinary frame with the CHAT_MSG_ events registered on it.
-- That is what feeds this window, and it has to be a registration of our own
-- rather than a hook on Blizzard's frames, because which messages a Blizzard
-- chat frame receives is a per character setting the player owns: a guild tab
-- turned off in the client's own chat settings is a guild message our window
-- would never see if we were listening through it.
--
-- The claim is ChatFrame_AddMessageEventFilter, which is FrameXML's own
-- extension point and the supported way to stop a message reaching every
-- Blizzard chat frame at once. It exists so the conversation is not drawn
-- twice, once here and once behind, which is exactly the doubled, unreadable
-- screen this part was asked to replace.
--
-- Nothing is hidden and nothing is unregistered. Blizzard's window keeps
-- everything we do not claim, which is loot, experience, faction, system text,
-- the combat log and every other addon's output, including this one's. That
-- is deliberate: a chat replacement that hides the frame every addon prints to
-- is a chat replacement that eats half of what the game says to you, and there
-- is no supported way to know which of the lines arriving at AddMessage came
-- from an event we already drew.
--
-- Turning the claim off leaves both windows drawing, which is a real thing to
-- want for a session or two while you decide whether this one is better.
--------------------------------------------------------------------------

-- The three streams. A line can be in more than one, and most whispers from
-- somebody on your list are in all three.
Feed.CHAT = "chat"
Feed.WHISPER = "whisper"
Feed.PEOPLE = "people"

-- How many lines are held for a window that does not exist yet. The events
-- start at load and the window is built at PLAYER_LOGIN, and between those two
-- moments the client replays whatever the server sent while you were loading.
local PENDING = 100

--------------------------------------------------------------------------
-- What each event is
--
-- tag      what is written in front of the name, in square brackets. One or
--          two letters, because it is read a thousand times an evening and
--          "Party" is six characters of the width that a message could use.
-- color    the key into the client's own ChatTypeInfo, so a player who has
--          recoloured guild chat in the client's settings gets that colour
--          here too. Falling back to the theme where the client has no table.
-- whisper  whether it belongs in the whispers stream as well
-- emote    the message is already a whole sentence with the name in it, so it
--          is drawn without a name and without a colon
-- target   the person the line is about is the recipient rather than the
--          sender, which is what an outgoing whisper is
--------------------------------------------------------------------------

local KINDS = {
	CHAT_MSG_SAY                  = { tag = "s",  color = "SAY" },
	CHAT_MSG_YELL                 = { tag = "y",  color = "YELL" },
	CHAT_MSG_EMOTE                = { tag = "e",  color = "EMOTE" },
	CHAT_MSG_TEXT_EMOTE           = { tag = "e",  color = "EMOTE", emote = true },
	CHAT_MSG_PARTY                = { tag = "p",  color = "PARTY" },
	CHAT_MSG_PARTY_LEADER         = { tag = "p",  color = "PARTY_LEADER" },
	CHAT_MSG_RAID                 = { tag = "r",  color = "RAID" },
	CHAT_MSG_RAID_LEADER          = { tag = "r",  color = "RAID_LEADER" },
	CHAT_MSG_RAID_WARNING         = { tag = "rw", color = "RAID_WARNING" },
	CHAT_MSG_INSTANCE_CHAT        = { tag = "i",  color = "INSTANCE_CHAT" },
	CHAT_MSG_INSTANCE_CHAT_LEADER = { tag = "i",  color = "INSTANCE_CHAT_LEADER" },
	CHAT_MSG_GUILD                = { tag = "g",  color = "GUILD" },
	CHAT_MSG_OFFICER              = { tag = "o",  color = "OFFICER" },
	CHAT_MSG_WHISPER              = { tag = "w",  color = "WHISPER", whisper = true },
	CHAT_MSG_WHISPER_INFORM       = { tag = "to", color = "WHISPER_INFORM", whisper = true, target = true },
	CHAT_MSG_BN_WHISPER           = { tag = "w",  color = "BN_WHISPER", whisper = true },
	CHAT_MSG_BN_WHISPER_INFORM    = { tag = "to", color = "BN_WHISPER_INFORM", whisper = true, target = true },
	-- What comes back when you whisper somebody who is away. It is addressed to
	-- you about a conversation you started, so it belongs where that
	-- conversation is.
	CHAT_MSG_AFK                  = { tag = "w",  color = "AFK", whisper = true, target = true },
	CHAT_MSG_DND                  = { tag = "w",  color = "DND", whisper = true, target = true },
}

-- The numbered channels are their own decision and their own setting. General
-- and Trade are most of the volume in a city and none of the conversation, and
-- the complaint this part answers is a window nobody could read. They stay in
-- Blizzard's frame unless you ask for them.
local CHANNEL_EVENT = "CHAT_MSG_CHANNEL"
KINDS[CHANNEL_EVENT] = { tag = "c", color = "CHANNEL", channel = true }

--------------------------------------------------------------------------

-- Set by whoever is drawing. Same shape as ns.Perf.OnSample: this file
-- produces, something else decides what a produced line looks like on screen.
Feed.OnLine = nil

local pending = {}
local applied = false
local claimed = {}
local filtered = 0

-- Whether the window that draws this is on screen. Set by whoever draws, the
-- same as Feed.OnLine is, and read by Claiming below.
local watched = false

local frame = CreateFrame("Frame")

--------------------------------------------------------------------------
-- Building a line
--------------------------------------------------------------------------

local GRAY = "|cff6b6b73%s|r"

local function Stamp()
	if not ns.db.chatStamp then
		return ""
	end
	return GRAY:format(date("%H:%M")) .. " "
end

-- The class colour of whoever spoke, as an escape code.
--
-- The GUID is the only reliable way to it: the client puts one on every chat
-- event and GetPlayerInfoByGUID reads the class straight out of it, for anyone,
-- in or out of your group. ns.Unit.Color owns the palette so the name in this
-- window is the colour that name is on a nameplate and in the meters.
--
-- White where the client will not say, which is a Battle.net whisper, a system
-- line and anything on a client with no GUID on the event.
local function NameColor(guid)
	if type(guid) ~= "string" or guid == "" then
		return "ffffffff"
	end
	if type(_G.GetPlayerInfoByGUID) ~= "function" then
		return "ffffffff"
	end
	-- The second return, not the first. The first is the class in this client's
	-- language and the palette is keyed by the English token, so taking the one
	-- that reads right in a debugger gives every name white on a French client.
	local ok, _, class = pcall(_G.GetPlayerInfoByGUID, guid)
	if not ok then
		return "ffffffff"
	end
	return ns.Unit.Color.ClassHex(class)
end

-- The name, drawn as a link so a click can answer it. The link carries the
-- full name including any realm, because that is what a whisper has to be
-- addressed to; the label is the short one, because the realm is noise in a
-- window this narrow.
local function NameLink(name, guid)
	local shown = name:gsub("%-.*$", "")
	return ("|Hplayer:%s|h|c%s%s|r|h"):format(name, NameColor(guid), shown)
end

-- Which colour the whole line is drawn in. The client's own table first, so a
-- player who has recoloured a channel in the client's chat settings sees that
-- colour here; the theme's ordinary text colour where the client has no table
-- or no entry for this kind.
local function LineColor(key)
	local info = _G.ChatTypeInfo and _G.ChatTypeInfo[key]
	if info and info.r then
		return info.r, info.g, info.b
	end
	local text = ns.UI.Color.text
	return text[1], text[2], text[3]
end

--------------------------------------------------------------------------
-- One message
--
-- The client's chat events all carry the same eleven arguments in the same
-- order on both clients, and only four of them matter here: the text, who said
-- it, which numbered channel it came from and the GUID. They are named on the
-- way in rather than indexed at each use.
--------------------------------------------------------------------------

local function Emit(streams, line, key, important)
	local r, g, b = LineColor(key)
	if not Feed.OnLine then
		if #pending < PENDING then
			pending[#pending + 1] = { streams = streams, line = line, r = r, g = g, b = b,
				important = important }
		end
		return false
	end
	Feed.OnLine(streams, line, r, g, b, important)
	return true
end

function Feed.Handle(event, text, sender, _, _, target, _, _, channelIndex,
	channelName, _, _, guid)
	local kind = KINDS[event]
	if not kind or type(text) ~= "string" then
		return false
	end

	local who = kind.target and target or sender
	-- An outgoing whisper says who it went to and the client puts that in the
	-- target argument on some events and in the sender argument on others. The
	-- sender is the fallback, because a line with no name at all is a line you
	-- cannot answer.
	if type(who) ~= "string" or who == "" then
		who = sender
	end

	local entry = ns.People.Match(who)
	local streams = { Feed.CHAT }
	if kind.whisper then
		streams[#streams + 1] = Feed.WHISPER
	end
	if entry then
		streams[#streams + 1] = Feed.PEOPLE
	end

	local tag = kind.tag
	if kind.channel then
		-- The number is what you type to answer it, so it is the number that is
		-- worth the two characters rather than the word behind it.
		tag = tostring(channelIndex or channelName or "c")
	end

	local body
	if kind.emote then
		-- A text emote arrives as a finished sentence with the name already in
		-- it, so a name and a colon in front of it would say it twice.
		body = text
	elseif type(who) == "string" and who ~= "" then
		local name = NameLink(who, guid)
		if event == "CHAT_MSG_EMOTE" then
			body = ("%s %s"):format(name, text)
		else
			body = ("%s: %s"):format(name, text)
		end
	else
		body = text
	end

	local line = ("%s%s %s"):format(Stamp(), GRAY:format("[" .. tag .. "]"), body)
	Emit(streams, line, kind.color, entry ~= nil)
	return true
end

--------------------------------------------------------------------------
-- Turning it on and off
--
-- Both halves are reversible in one call, because the whole contract this addon
-- holds itself to is that off is a state rather than a reload. The events come
-- off the frame and the filters come out of FrameXML's list, and Blizzard's
-- window is drawing the conversation again the moment the second one lands.
--------------------------------------------------------------------------

local function Wanted(event)
	if event == CHANNEL_EVENT then
		return ns.db.chat and ns.db.chatChannels
	end
	return ns.db.chat
end

-- Whether a line may be taken out of Blizzard's frames.
--
-- Three things have to hold and the third is the one that was missing. The
-- setting has to be on, something has to be drawing, and that something has to
-- be on screen.
--
-- A filter installed while nothing is drawing does not move the conversation,
-- it deletes it: the line comes out of Blizzard's frames and lands in a window
-- that is closed, or in no window at all when the build failed, and the only
-- symptom is a chat log that has gone quiet. That is not a corner case. The
-- window has a close box, the closed state is saved, and Feed.Apply runs again
-- at every login, so one press deleted every say, party, guild, raid and
-- whisper line from the screen until the player found /wk chat.
--
-- The claim is also asked for at ADDON_LOADED, which is before the window
-- exists at all. Holding it back until something is attached is what keeps the
-- client's login replay in Blizzard's window instead of in the hundred line
-- pending buffer, where everything past the hundredth was dropped.
local function Claiming()
	return ns.db.chat and ns.db.chatClaim and Feed.OnLine ~= nil and watched
end

-- A filter per claimed event, made once and kept, because
-- ChatFrame_RemoveMessageEventFilter matches on the function itself and a fresh
-- closure would remove nothing and leave the old one filtering forever.
local filters = {}

-- The filter asks the same question again for every message it is handed,
-- rather than trusting that it was taken out of FrameXML's list when the answer
-- last changed.
--
-- Installing and removing is now the cheap half. It saves FrameXML a call per
-- message per frame and it is worth doing, but it is not what makes this
-- correct: correctness is that a filter which outlives its reason hands the
-- line back instead of deleting it. Anything that forgets to reapply, an
-- unhandled error between a hide and the reapply, a path added later that moves
-- the window without telling this file, costs a wasted call and nothing else.
--
-- That is the shape the first version got wrong. It had two installations, a
-- filter that deletes and a window that draws, kept in step by whoever
-- remembered to call both. They went out of step the moment the window was
-- closed and the conversation was drawn nowhere at all.
local function FilterFor(event)
	if not filters[event] then
		filters[event] = function()
			if not Claiming() then
				return false
			end
			filtered = filtered + 1
			return true
		end
	end
	return filters[event]
end

function Feed.Installed()
	return type(_G.ChatFrame_AddMessageEventFilter) == "function"
		and type(_G.ChatFrame_RemoveMessageEventFilter) == "function"
end

local function Claim(event, on)
	if not Feed.Installed() then
		return false
	end
	if on and not claimed[event] then
		_G.ChatFrame_AddMessageEventFilter(event, FilterFor(event))
		claimed[event] = true
		return true
	end
	if not on and claimed[event] then
		_G.ChatFrame_RemoveMessageEventFilter(event, FilterFor(event))
		claimed[event] = nil
		return true
	end
	return false
end

function Feed.Apply()
	applied = true
	local claiming = Claiming()
	for event in pairs(KINDS) do
		local want = Wanted(event)
		-- An event this client does not know raises on registration rather than
		-- answering, and the set here spans two clients, so every registration
		-- is pcalled. Losing one costs that kind of message.
		if want then
			pcall(frame.RegisterEvent, frame, event)
		else
			pcall(frame.UnregisterEvent, frame, event)
		end
		Claim(event, want and claiming)
	end
	return true
end

-- Whoever draws calls this once it is ready to draw, and gets whatever arrived
-- while it was being built. The client replays a good deal at login and a guild
-- greeting you never saw because the window was one frame behind is exactly the
-- line you wanted.
function Feed.Attach(onLine)
	Feed.OnLine = onLine
	-- Attaching moves what Claiming answers, so the filters are worked out
	-- again here rather than left to the caller. A caller that forgot the
	-- second call is a chat window that has gone quiet.
	if applied then
		Feed.Apply()
	end
	if not onLine then
		return 0
	end
	local held = #pending
	for _, held_line in ipairs(pending) do
		onLine(held_line.streams, held_line.line, held_line.r, held_line.g, held_line.b,
			held_line.important)
	end
	pending = {}
	return held
end

-- Told by whoever draws, whenever it comes up or goes away. The claim on
-- Blizzard's frames follows the window, because a window you cannot see is not
-- drawing the conversation it took.
function Feed.Watched(shown)
	shown = shown and true or false
	if watched == shown then
		return false
	end
	watched = shown
	Feed.Apply()
	return true
end

function Feed.Describe()
	if not ns.db.chat then
		return "off, Blizzard's chat draws everything"
	end
	if not ns.db.chatClaim then
		return "on, and Blizzard's chat still draws the same lines"
	end
	if not Feed.Installed() then
		return "on, but this client has no message filter so both windows draw"
	end
	if not Claiming() then
		return "on, and handed back to Blizzard's chat while this window is closed"
	end
	return ("on, %d lines taken out of Blizzard's frames"):format(filtered)
end

function Feed.Claimed()
	local count = 0
	for _ in pairs(claimed) do
		count = count + 1
	end
	return count
end

--------------------------------------------------------------------------

frame:SetScript("OnEvent", function(_, event, ...)
	Feed.Handle(event, ...)
end)

-- Registered at ADDON_LOADED rather than at file load, because Wanted reads the
-- saved settings and there are none until then. Nothing is missed by waiting:
-- the client replays the login traffic after that point.
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
	if name ~= ADDON then
		return
	end
	if not applied then
		Feed.Apply()
	end
	self:UnregisterEvent("ADDON_LOADED")
end)
