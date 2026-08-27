local ADDON, ns = ...

local Blizz = {}
ns.ChatBlizzard = Blizz

--------------------------------------------------------------------------
-- Blizzard's chat window, off the screen
--
-- The switch is `hide Blizzard's chat window`, and it sits with the other six
-- in UnitFrames/Blizzard.lua, because a player who can see two chat windows
-- should find the line that turns one off on the page where every other line
-- like it lives. What is here is the part that would not fit on that line.
--
-- Everything the game says to you that is not somebody talking arrives at that
-- window and nowhere else. Loot, experience, reputation, your own repair bill,
-- every addon's output, this addon's own. Hiding the frame without doing
-- anything else would delete all of it.
--
-- So hiding is three things that only work together.
--
--   The frames go off the screen. Every chat frame, its tab, its buttons and
--   the furniture round them, through ns.Strip, which replaces a frame's Show
--   with its Hide and survives the client showing it again.
--
--   Everything that would have been drawn in the default frame is forwarded to
--   the System room in our window. That is one hook on AddMessage, and it is
--   allowed to be a plain forward with no filtering because of the third piece.
--
--   The claim is forced on. Chat/Feed.lua takes every conversation event out of
--   Blizzard's frames before FrameXML draws it, so what is left arriving at
--   AddMessage is exactly what this addon did not capture. That is the
--   difference between forwarding and doubling, and it is the reason the README
--   used to say this could not be done: with the claim off there is no way to
--   know which lines at AddMessage came from an event we already drew.
--
-- **Hiding follows the window.** Our window closed and Blizzard's hidden is a
-- game with no chat at all, so closing ours puts theirs back on the next call,
-- the same way the claim does and for the same reason. That coupling is not a
-- nicety: the first version of the claim did not have it and one press of a
-- close box deleted every line of conversation from the screen.
--
-- Nothing here is protected and nothing here is secure, so all of it works in
-- combat. The client's own edit box is deliberately left alone: it is what
-- ChatEdit_SendText needs to run a slash command, and it comes up over whatever
-- is hidden behind it.
--------------------------------------------------------------------------

-- What goes away besides the numbered frames. Every name is probed before it is
-- touched, because these differ between the two clients this addon ships for
-- and a missing one has to cost that frame rather than the feature.
local FURNITURE = {
	"GeneralDockManager",
	"ChatFrameMenuButton",
	"ChatFrameChannelButton",
	"ChatFrameToggleVoiceDeafenButton",
	"ChatFrameToggleVoiceMuteButton",
	"QuickJoinToastButton",
	"FriendsMicroButton",
}

-- Frames this file has taken down, so the same set goes back.
--
-- ns.Unstrip shows what it restores, which is right for every other caller: a
-- frame this addon replaces was on the screen before it did. It is wrong here,
-- because eight of the ten chat frames have never been on screen in most
-- installs and putting the window back would turn on eight tabs nobody has ever
-- opened. So only a frame that was showing when it was taken is stripped at all.
local held = {}
local hiding = false
local forwarding = false

local function Windows()
	local count = _G.NUM_CHAT_WINDOWS
	if type(count) ~= "number" or count < 1 then
		return 10
	end
	return count
end

local function Take(frame)
	if type(frame) ~= "table" or type(frame.Hide) ~= "function" then
		return false
	end
	if not held[frame] then
		if not frame:IsShown() then
			return false
		end
		held[frame] = true
	end
	return ns.Strip(frame)
end

local function Give(frame)
	if type(frame) ~= "table" or not held[frame] then
		return false
	end
	return ns.Unstrip(frame)
end

--------------------------------------------------------------------------
-- Everything the default frame is handed
--
-- hooksecurefunc on the method rather than a replacement of it, so the client's
-- own AddMessage still runs and the frame keeps its scrollback. Turning the
-- switch off puts the window back with the evening in it rather than empty.
--
-- Installed once and never removed, because a hook cannot be. The flag is what
-- turns it off, which costs one comparison per line drawn into a window that is
-- not on the screen.
--------------------------------------------------------------------------

local function Forward()
	if forwarding then
		return true
	end
	local frame = _G.DEFAULT_CHAT_FRAME
	if type(frame) ~= "table" or type(frame.AddMessage) ~= "function" then
		return false
	end
	if type(_G.hooksecurefunc) ~= "function" then
		return false
	end
	forwarding = pcall(_G.hooksecurefunc, frame, "AddMessage", function(_, text, r, g, b)
		if hiding then
			ns.ChatFeed.System(text, r, g, b)
		end
	end)
	return forwarding
end

--------------------------------------------------------------------------

-- Whether the client's window should be off the screen right now. Three things
-- have to hold, and the third is the one that keeps this safe: our window has to
-- be open, or there would be nowhere at all for the game to talk to you.
function Blizz.Wanted()
	return (ns.db.chat and ns.db.hideBlizzChat and ns.ChatWindow.Shown()) and true or false
end

function Blizz.Apply()
	local wanted = Blizz.Wanted()
	-- Asked again on every apply rather than once, and before the comparison
	-- below rather than after it. hooksecurefunc is probed like everything else
	-- the client might not have, and a client that grows one later, or an addon
	-- that installs it after us, would otherwise leave the forward off for the
	-- session with the window still hidden, which is the one failure here that
	-- loses lines. It costs one comparison once it has taken.
	if wanted then
		Forward()
	end

	if wanted == hiding then
		return false
	end
	hiding = wanted

	local move = wanted and Take or Give
	for index = 1, Windows() do
		local frame = _G["ChatFrame" .. index]
		if frame then
			move(frame)
			move(_G["ChatFrame" .. index .. "Tab"])
			move(_G["ChatFrame" .. index .. "ButtonFrame"])
		end
	end

	for _, name in ipairs(FURNITURE) do
		move(_G[name])
	end
	return true
end

function Blizz.Hiding()
	return hiding
end

function Blizz.Count()
	local count = 0
	for _ in pairs(held) do
		count = count + 1
	end
	return count
end

function Blizz.Describe()
	if not ns.db.hideBlizzChat then
		return "on screen"
	end
	if not hiding then
		return "on screen while this window is closed"
	end
	if not forwarding then
		return "hidden, and this client would not let the addon forward what it drew"
	end
	return ("hidden, %d frames held"):format(Blizz.Count())
end

--------------------------------------------------------------------------

-- Registered with the switch it belongs to, so `/wk hide chat`, the panel's own
-- line and `/wk reset` all reach this file without any of them naming it.
ns.BlizzHide.Also(Blizz.Apply)
