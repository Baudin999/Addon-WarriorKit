local ADDON, ns = ...

-- The fanfare when you level.
--
-- Five seconds of "You're the Best" over the client's own ding, and the whole
-- of what this part does. It is not a convenience the way the four chores above
-- it are: nothing here saves you a keypress and the addon is no better at
-- anything for having it. It is here because a level is the one moment in this
-- game that is entirely yours, the client marks it with a chime you stopped
-- hearing at about level twelve, and a horn section does not go unheard.
--
-- The snippet is the one from BestAround, byte for byte, which is where
-- everybody who has heard this joke heard it: LittleJoey's addon from 2007,
-- fixed for 6.0 by Nephyrin, four files and one of them the song. Media/
-- BestAround-LICENSE.txt says where it came from and what is and is not ours,
-- and it is worth reading before this addon goes anywhere strangers can
-- download it.
--
-- This part owns no frame past the one it listens on and draws nothing, so
-- nothing here is on a ticker.

local Fanfare = {}
ns.Fanfare = Fanfare

-- The file, and the only line in the addon that names it. The client's paths
-- are Interface\AddOns\<folder>\..., with the folder being what the addon is
-- installed as rather than what the TOC calls itself, which is why this is
-- written out rather than built from ADDON.
local SOUND = "Interface\\AddOns\\WarriorKit\\Media\\BestAround.mp3"

-- Master rather than the SFX channel the call defaults to.
--
-- SFX is where a spell landing and a sword hitting go, and it is the slider
-- people pull down to nothing in a raid. A level up happens about forty times
-- in a character's life and it is not a combat noise; putting it on the master
-- volume means the one person who turned their sound effects off still gets it,
-- and the one who turned everything off still does not.
local CHANNEL = "Master"

-- How long the clip runs, in seconds, measured off the file itself.
--
-- It is a throttle and not a timer: nothing is scheduled and nothing is
-- stopped. A quest turned in at the right moment levels you twice, the client
-- fires PLAYER_LEVEL_UP once per level, and two copies of the same five seconds
-- a frame apart is not a fanfare, it is a fault.
local CLIP = 5.1

local frame

-- When the clip last started, on the client's own clock, and how many times it
-- has since login. The count is the only thing the panel and the slash word
-- have to report, and it is a count rather than a list for the reason the
-- thank-you count is: what levels you took tonight is nobody's business but
-- yours.
local playedAt = 0
local plays = 0

-- Why the last attempt did not play, or nil if it did. Kept because all three
-- of the ways this can fail are silent by nature: a muted channel, a client
-- that will not take the call, and a file that is not where the path says. A
-- fanfare that does not sound and does not say why is indistinguishable from a
-- setting somebody forgot they turned off.
local lastWhy

-- One attempt, and how much the client said about it.
--
-- select("#") rather than three plain names, because "answered nil" and "said
-- nothing at all" are different answers and only the first of them is a muted
-- channel. Modern builds hand back willPlay and a handle; the two this addon
-- ships for are not proven to hand back anything, and reading a return that was
-- never made as a refusal would report every fanfare that played fine as one
-- that did not. Buffs/Upkeep.lua counts its returns for the same reason.
local function Speak(...)
	return select("#", ...), ...
end

-- Play it now, whatever the setting says, and answer what happened.
--
-- The setting is the caller's business: OnEvent is only registered while it is
-- on, and `/wk ding` is a press, which is the one thing in this addon that is
-- allowed to ignore a switch because you just asked for it by name.
function Fanfare.Play()
	local play = _G.PlaySoundFile
	if type(play) ~= "function" then
		lastWhy = "this client has no PlaySoundFile to hand the file to"
		return false, lastWhy
	end

	local now = GetTime()
	if now - playedAt < CLIP then
		return false, "it is already playing"
	end

	-- pcalled for the reason Comfort/Camera.lua pcalls SetCVar: nothing
	-- installed on either of these clients calls this with a channel, a build
	-- that does not take the second argument raises rather than ignoring it,
	-- and an error at every level up is worse than a fanfare on the wrong
	-- slider. The bare call is the fallback, not the first try, because the
	-- channel is the whole reason a raider hears this at all.
	local said, ok, willPlay = Speak(pcall(play, SOUND, CHANNEL))
	if not ok then
		said, ok, willPlay = Speak(pcall(play, SOUND))
	end
	if not ok then
		lastWhy = "this client would not take the file"
		return false, lastWhy
	end

	playedAt = now

	-- said counts pcall's own true as well, so one return is a client that
	-- answered nothing and anything more is a client with an opinion.
	if said > 1 and not willPlay then
		lastWhy = "the master volume is down or the channel is muted"
		return false, lastWhy
	end

	plays = plays + 1
	lastWhy = nil
	return true
end

-- Registered and unregistered rather than left on with a branch inside, the
-- same as Thanks.lua and for a smaller version of the same reason: off should
-- mean the addon is not listening, so a setting turned off cannot be the thing
-- that made a level up stutter.
function Fanfare.Apply()
	if not frame then
		frame = CreateFrame("Frame")
		frame:SetScript("OnEvent", function()
			Fanfare.Play()
		end)
	end
	if ns.db.levelFanfare then
		frame:RegisterEvent("PLAYER_LEVEL_UP")
	else
		frame:UnregisterEvent("PLAYER_LEVEL_UP")
	end
end

function Fanfare.Describe()
	if type(_G.PlaySoundFile) ~= "function" then
		return "this client has no PlaySoundFile, so nothing would play"
	end
	if not ns.db.levelFanfare then
		return "off, a level up is the client's own chime and nothing else"
	end
	if lastWhy then
		return "on, and the last one did not sound: " .. lastWhy
	end
	if plays == 0 then
		return "on, no level up yet this session"
	end
	return ("on, %d level%s so far this session"):format(plays, plays == 1 and "" or "s")
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
	Fanfare.Apply()
end)
