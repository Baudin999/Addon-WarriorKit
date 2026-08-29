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
local chat, region, child, GUILD = H.chat, H.region, H.child, H.GUILD

-- The client's own per type colours. Two entries with numbers that are not the
-- theme's, so a line that fell back to the theme is visible as a wrong colour
-- rather than as a coincidence.
-- The font the client draws its own chat line in, so the restyle in
-- Chat/Field.lua has something of Blizzard's to take back off.
_G.ChatFontNormal = region("font", nil, "ChatFontNormal")

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

----------------------------------------------------------------------
-- The client's own line
--
-- Modelled rather than stubbed, because the window types into it now. There is
-- no edit box of the addon's any more: Chat/Field.lua borrows the client's, and
-- every assertion about what is in the line, where the line sits and what the
-- enter key does reads this frame.
--
-- OnEnterPressed is set here and not by the addon, and that is the property
-- under test. In the game it is set in XML and never touched, which is what
-- lets a protected command finish; here it is set once by this file, so a
-- version of the addon that reached for SetScript would overwrite it and every
-- send in the suite would stop recording.
----------------------------------------------------------------------

local function EditBox(index)
	local name = ("ChatFrame%dEditBox"):format(index)
	local box = region("editbox", nil, name)
	box.parent = _G["ChatFrame" .. index]
	box:SetPoint("BOTTOMLEFT", _G.UIParent, "BOTTOMLEFT", 16, 24)
	box:Hide()
	-- Blizzard's three border pieces and the focus glow, as real regions of the
	-- frame, because Chat/Field.lua walks GetRegions rather than naming them:
	-- a stub that only answered by name could not tell the walk from a version
	-- that had gone back to the list.
	for _, part in ipairs({ "Left", "Right", "Mid" }) do
		child("texture", box, name .. part)
	end
	box.focusLeft = child("texture", box)
	box.focusRight = child("texture", box)
	box.focusMid = child("texture", box)
	-- And the border a newer client wraps in a frame of its own, which is the
	-- shape that got through the first version of the strip and drew a bright
	-- rounded rectangle across the foot of a window with no other edge on it.
	-- Modelled here so a walk that stops at the field's own regions fails rather
	-- than reporting that it found nothing to hide.
	box.NineSlice = child("frame", box, name .. "NineSlice")
	for _, corner in ipairs({ "TopLeft", "TopRight", "BottomLeft", "BottomRight" }) do
		child("texture", box.NineSlice, name .. "NineSlice" .. corner)
	end
	-- The word in front of the line, which is what FrameXML draws instead of the
	-- slash you typed, and the punctuation after it.
	box.header = child("fontstring", box, name .. "Header")
	box.header:SetWidth(40)
	child("fontstring", box, name .. "HeaderSuffix"):SetWidth(6)
	box:SetScript("OnEnterPressed", function(self)
		_G.ChatEdit_SendText(self, 1)
		self:SetText("")
		self:ClearFocus()
		self:Hide()
	end)
	return box
end

-- Which line the client would send from. The first, because that is the answer
-- on an install where nobody has ever typed in a second window, and the addon
-- has to take the client's answer rather than name a frame itself.
_G.ChatEdit_ChooseBoxForSend = function()
	return _G.ChatFrame1EditBox
end

-- Opening the line, in the order FrameXML does it, and the order is the whole
-- reason this is modelled: the client activates the field, which raises the
-- focus, and only then writes the text the key asked for. Anything the addon
-- put in the line while it was activating is blanked by that last write, and
-- Chat/Field.lua exists to survive it.
_G.ChatEdit_ActivateChat = function(box)
	box:Show()
	_G.ChatEdit_UpdateHeader(box)
	box:SetFocus()
end

-- The client writing its own font, colour and inset over whatever an addon put
-- there, which it does on activation and on every change of channel. Modelled
-- rather than stubbed, because a style applied once at login and never again
-- looks right until the first whisper, and that is exactly the bug a no-op here
-- would hide: the addon would set its colours, nothing would take them off, and
-- every assertion about them would pass on a client that does.
--
-- The numbers are Blizzard's own shape: the channel's colour on the text, the
-- channel's word in the header, and an inset derived from the header's width.
_G.ChatEdit_UpdateHeader = function(box)
	local kind = box:GetAttribute("chatType") or "SAY"
	local info = _G.ChatTypeInfo[kind] or _G.ChatTypeInfo.SAY
	box:SetTextColor(info.r, info.g, info.b)
	box:SetFontObject(_G.ChatFontNormal)
	if box.header then
		box.header:SetText(kind)
		box.header:SetFontObject(_G.ChatFontNormal)
		box.header:ClearAllPoints()
		box.header:SetPoint("LEFT", box, "LEFT", 15, 0)
	end
	box:SetTextInsets(15 + ((box.header and box.header:GetWidth()) or 0), 13, 0, 0)
end

_G.ChatEdit_DeactivateChat = function(box)
	box:ClearFocus()
	box:Hide()
end

-- The client's own chat keys, as the two functions the bindings run. The addon
-- binds neither of them any more, so this is how a section presses enter.
_G.ChatFrame_OpenChat = function(text)
	local box = _G.ChatEdit_ChooseBoxForSend()
	_G.ChatEdit_ActivateChat(box)
	box:SetText(text or "")
	return box
end

_G.ChatEdit_SendText = function(box)
	chat.slash[#chat.slash + 1] = box:GetText()
end

-- The client's own answer to whether a slash word ends in a protected call.
-- Nothing in the addon asks it any more, and it is left here because the
-- section asserts that: a version that grew a list of special words back would
-- have something to consult, and the check that nothing does is worth keeping.
_G.IsSecureCmd = function(command)
	return type(command) == "string"
		and (command:upper() == "/LOGOUT" or command:upper() == "/QUIT")
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
	-- One line per window, made here rather than beside the frame it belongs
	-- to, because the addon dresses every one of them: which line the client
	-- opens is its own choice, and a line the addon never dressed would come up
	-- in Blizzard's art in the middle of our footer.
	EditBox(index)
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
