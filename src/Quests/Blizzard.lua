local ADDON, ns = ...

local Blizz = {}
ns.QuestBlizzard = Blizz

--------------------------------------------------------------------------
-- Blizzard's quest log, out of the way
--
-- **This one goes in the attic, and the mail window does not.**
--
-- That difference is the whole file and it is worth stating, because
-- Mail/Blizzard.lua argues at length that its frame must be parked rather than
-- caged, and the next person to read these two files together will wonder which
-- of them is wrong.
--
-- Neither. MailFrame is a live interaction with the server: the client ends the
-- mailbox session when that frame stops being drawn, so hiding it is what closes
-- the mailbox. QuestLogFrame is not. Nothing about your quest log is a session,
-- every quest API works with the frame nowhere near the screen, and the
-- selection cursor those APIs read is global state rather than the frame's.
-- Quests/Client.lua reads and writes it with the frame caged and the client
-- neither notices nor cares.
--
-- So this takes the stronger mechanism. Core/Attic.lua re-parents the frame
-- into a room that is hidden, and a frame whose parent is hidden is not drawn
-- whatever anything calls on it. Parking would leave a window off the side of
-- the screen that a client relayout could put back; the cage cannot be undone
-- except by somebody else's SetParent, and Attic.Sweep is what checks that.
--
-- **The key has to come with it.** Hiding the window and leaving L bound to the
-- client's own toggle is a log you cannot open, which is a worse state than
-- either window on its own. ToggleQuestLog is a plain global on both of these
-- clients, so it is replaced with one that opens this addon's window, and the
-- original is kept so the switch can put it back. That is a global function
-- swap and it is the only one in the addon, which is why it is here rather than
-- anywhere subtler: one file, named after what it does to Blizzard's frame.
--
-- **The switch is `hide Blizzard's quest log`.** Off, both windows work and the
-- key opens theirs, which is worth having while anything here is unconfirmed in
-- game: everything this window cannot do, the client's can, and it is one tick
-- box away.
--------------------------------------------------------------------------

-- The frames that make up the client's log. QuestLogFrame is the window;
-- QuestLogDetailFrame is the separate panel newer builds split the quest text
-- onto, and it is probed rather than assumed because Classic Era does not have
-- one. Every name is probed before it is touched, the same as the chat
-- window's furniture list.
local FRAMES = {
	"QuestLogFrame",
	"QuestLogDetailFrame",
}

-- What the client's L key called before this addon took it. Kept rather than
-- rebuilt, because the switch has to be able to hand it back exactly.
local original = nil

local caged = false

local function Frame(name)
	local frame = _G[name]
	if type(frame) ~= "table" or type(frame.GetParent) ~= "function" then
		return nil
	end
	return frame
end

--------------------------------------------------------------------------
-- The key
--------------------------------------------------------------------------

-- Whoever is holding ToggleQuestLog now, remembered once. Called before the
-- swap and never after, so a second addon that wrapped the same global after us
-- is not swallowed by a later re-apply.
local function Remember()
	if original == nil and type(_G.ToggleQuestLog) == "function" then
		original = _G.ToggleQuestLog
	end
	return original ~= nil
end

local function TakeKey()
	if not Remember() then
		return false
	end
	_G.ToggleQuestLog = function()
		ns.QuestWindow.Toggle()
	end
	return true
end

local function GiveKey()
	if type(original) ~= "function" then
		return false
	end
	_G.ToggleQuestLog = original
	return true
end

--------------------------------------------------------------------------
-- The frames
--------------------------------------------------------------------------

local function Cage()
	local complete = true
	for _, name in ipairs(FRAMES) do
		local frame = Frame(name)
		if frame and not ns.Attic.Vanish(frame) then
			complete = false
		end
	end
	return complete
end

local function Release()
	local complete = true
	for _, name in ipairs(FRAMES) do
		local frame = Frame(name)
		if frame and not ns.Attic.Return(frame) then
			complete = false
		end
	end
	return complete
end

--------------------------------------------------------------------------

-- Whether the client's window should be out of the way right now.
--
-- Two things, and no third. The mail window adds "and ours is open", because a
-- mailbox with no window at all is a mailbox you cannot use. This one does not
-- need it: the key opens ours, so there is never a moment where the log is
-- unreachable, and a log caged only while our window happens to be up would
-- flicker Blizzard's frame onto the screen every time ours closed.
function Blizz.Wanted()
	return (ns.db.quests and ns.db.questsHideBlizz) and true or false
end

function Blizz.Apply()
	local wanted = Blizz.Wanted()
	if wanted == caged then
		return false
	end
	caged = wanted
	if wanted then
		TakeKey()
		return Cage()
	end
	GiveKey()
	return Release()
end

function Blizz.Caged()
	return caged
end

function Blizz.Describe()
	if not ns.db.questsHideBlizz then
		return "on screen, and L opens it"
	end
	if not caged then
		return "on screen"
	end
	if type(original) ~= "function" then
		return "in the attic, and this client has no ToggleQuestLog to redirect"
	end
	return "in the attic, and L opens this one"
end
