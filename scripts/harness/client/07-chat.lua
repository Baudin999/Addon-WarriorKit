-- Chat and voice
--
-- Enough of the client's social surface for the chat part to run against.
--
-- The filter list is the one thing here that is not a recording stub. It is
-- FrameXML's own list, and Chat/Feed.lua both adds to it and takes back out of
-- it, so a stub that only counted calls could not tell a filter that was
-- removed from one that was added twice. It is modelled as the list it is, and
-- the chat section reads what is in it.

local H = ...
local chat, region, GUILD = H.chat, H.region, H.GUILD

-- The client's own per type colours. Two entries with numbers that are not the
-- theme's, so a line that fell back to the theme is visible as a wrong colour
-- rather than as a coincidence.
_G.ChatTypeInfo = {
	SAY = { r = 1, g = 1, b = 1 },
	PARTY = { r = 0.67, g = 0.67, b = 1 },
	GUILD = { r = 0.25, g = 1, b = 0.25 },
	WHISPER = { r = 1, g = 0.5, b = 1 },
	WHISPER_INFORM = { r = 1, g = 0.5, b = 1 },
	CHANNEL = { r = 1, g = 0.75, b = 0.75 },
}

_G.ChatFrame_AddMessageEventFilter = function(event, fn)
	chat.filters[event] = chat.filters[event] or {}
	local list = chat.filters[event]
	list[#list + 1] = fn
end

_G.ChatFrame_RemoveMessageEventFilter = function(event, fn)
	local list = chat.filters[event]
	if not list then
		return
	end
	for index = #list, 1, -1 do
		if list[index] == fn then
			table.remove(list, index)
		end
	end
end

-- Class by GUID, for the class colour on a name. The real one answers seven
-- values and the English token is the second, which is the whole reason this
-- returns two: a stub that answered one would let the addon read the localised
-- class and colour every name white on a French client without anything here
-- noticing.
_G.GetPlayerInfoByGUID = function(guid)
	local class = chat.classByGuid[guid]
	if not class then
		return nil
	end
	return class:sub(1, 1) .. class:sub(2):lower(), class
end

_G.SendChatMessage = function(text, kind, language, target)
	chat.sent[#chat.sent + 1] = { text = text, kind = kind, language = language, target = target }
end

_G.ChatFrame1EditBox = region("frame")
_G.ChatEdit_SendText = function(box)
	chat.slash[#chat.slash + 1] = box:GetText()
end

_G.SetItemRef = function(link) chat.link = link end
_G.SOUNDKIT = { TELL_MESSAGE = 3081 }
_G.PlaySound = function(id) chat.sound = id end
_G.IsInGuild = function() return chat.inGuild == true end

----------------------------------------------------------------------
-- The client's own chat window
--
-- Real frames rather than the no-op regions the rest of this file uses for
-- Blizzard's furniture, because Chat/Blizzard.lua hides them and puts them
-- back, and a stub that swallows Hide cannot tell the version that restores
-- what it took from the version that leaves the window off the screen forever.
--
-- Two windows and their tabs, which is enough to prove the walk runs over more
-- than the one it was written against.
----------------------------------------------------------------------

_G.NUM_CHAT_WINDOWS = 2
for index = 1, _G.NUM_CHAT_WINDOWS do
	region("frame", nil, "ChatFrame" .. index)
	region("frame", nil, "ChatFrame" .. index .. "Tab")
end
_G.ChatFrameMenuButton = region("frame", nil, "ChatFrameMenuButton")
_G.DEFAULT_CHAT_FRAME = _G.ChatFrame1


-- The communities, shaped the way the client's own Chat Channels window reads:
-- a club with more than one stream, and a second club with one. Every one of
-- those rows carries a voice button in game, which is the whole reason the
-- picker offers streams that have no voice channel behind them yet.
_G.C_Club = {
	GetSubscribedClubs = function()
		return {
			{ clubId = 11, name = "C & F" },
			{ clubId = 22, name = "Three Musketeers" },
		}
	end,
	GetStreams = function(clubId)
		if clubId == 11 then
			return { { streamId = 1, name = "General" }, { streamId = 2, name = "Home" } }
		end
		return { { streamId = 1, name = "General" } }
	end,
}

-- The voice service. Channels are keyed the way the addon asks for them: by
-- channel type for a party, and by club and stream for a community, which is
-- the split the addon makes because one of those pairs survives a logout and a
-- channelID does not.
_G.C_VoiceChat = {
	IsEnabled = function() return chat.voice.enabled end,
	IsLoggedIn = function() return chat.voice.loggedIn end,
	Login = function()
		chat.voice.calls[#chat.voice.calls + 1] = { what = "login" }
	end,
	GetChannelForChannelType = function(channelType)
		return chat.voice.channels[channelType]
	end,
	GetChannelForCommunityStream = function(clubId, streamId)
		return chat.voice.channels[("club:%s:%s"):format(tostring(clubId), tostring(streamId))]
	end,
	GetActiveChannelID = function() return chat.voice.active end,
	GetChannel = function(channelID)
		for _, channel in pairs(chat.voice.channels) do
			if channel.channelID == channelID then
				return channel
			end
		end
		return nil
	end,
	ActivateChannel = function(channelID)
		chat.voice.calls[#chat.voice.calls + 1] = { what = "activate", channelID = channelID }
		chat.voice.active = channelID
		for _, channel in pairs(chat.voice.channels) do
			if channel.channelID == channelID then
				channel.isActive = true
			end
		end
	end,
	RequestJoinChannelByChannelType = function(channelType, autoActivate)
		chat.voice.calls[#chat.voice.calls + 1] =
			{ what = "requestType", channelType = channelType, autoActivate = autoActivate }
	end,
	RequestJoinAndActivateCommunityStreamChannel = function(clubId, streamId)
		chat.voice.calls[#chat.voice.calls + 1] =
			{ what = "requestClub", clubId = clubId, streamId = streamId }
	end,
}

-- The client's Chat Channels window, which is where its voice roster and the
-- volume slider per person live. Counted rather than drawn: what the addon is
-- responsible for is asking for it, and a frame here would be a frame this file
-- invented rather than one the client has.
--
-- Blizzard_Channels is load on demand in the game, so the loaded probe answers
-- true and the load call is never reached. A run that reached it would be
-- testing this file's idea of LoadAddOn rather than the addon.
_G.IsAddOnLoaded = function(name)
	return name == "Blizzard_Channels"
end

_G.ToggleChannelFrame = function()
	chat.voice.channelWindow = (chat.voice.channelWindow or 0) + 1
end
