local ADDON, ns = ...

local Blizz = {}
ns.TalentBlizzard = Blizz

--------------------------------------------------------------------------
-- Blizzard's talent frame, out of the way
--
-- One frame and one key, and the argument for both is the character sheet's.
-- The client's talent window is not a live server session the way the mail
-- window is: every call this addon makes about your talents, spending a point
-- included, works with that frame nowhere near the screen. So it goes in the
-- attic, where a hidden parent beats every route the client has to put a frame
-- back, rather than being parked off the side where a relayout could return
-- it.
--
-- **Most of the time there is no frame to cage.** The client's talent window
-- is an addon of Blizzard's own, loaded the first time anything asks for it,
-- and the thing that asks is ToggleTalentFrame. Take that global and the
-- addon is never loaded at all, which is the cheapest cage there is. The frame
-- is still named below and still caged when it exists, because a second addon
-- can load Blizzard_TalentUI for reasons of its own and a window that appears
-- once an evening under ours is worse than one that never does.
--
-- **The key has to come with it.** Hiding the window and leaving N bound to
-- the client's own toggle is a talent window you cannot open, which is worse
-- than either window on its own. ToggleTalentFrame is a plain global on both
-- of these clients, so it is replaced with one that opens this addon's window
-- and the original is kept so the switch can hand it back exactly. No
-- override binding, unlike the character sheet: nothing on this window is
-- secure, so the plain global the client already routes the key through
-- opens it in a fight.
--
-- **The switch is the one on the Blizzard page.** There is one place in this
-- addon where a frame of the client's is switched on or off, it is the list
-- in UnitFrames/Blizzard.lua, and this file registers into it the way the
-- character sheet's does.
--------------------------------------------------------------------------

-- The window on the newer client and the one the oldest client called it.
-- Every name is probed before it is touched, and a name this client does not
-- carry costs one lookup against nil.
local FRAMES = {
	"PlayerTalentFrame",
	"TalentFrame",
}

-- The addon of Blizzard's own that builds the frame, watched so a frame that
-- arrives after login goes straight up rather than waiting for the pass.
local LOADS = "Blizzard_TalentUI"

-- What the client's N key called before this addon took it.
local original = nil

-- The client's own binding for its talent window. Two names because the two
-- clients this addon runs on do not agree.
local BINDINGS = { "TOGGLETALENTS", "TOGGLETALENTFRAME" }

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

-- Whoever is holding ToggleTalentFrame now, remembered once. Called before the
-- swap and never after, so a second addon that wrapped the same global after
-- us is not swallowed by a later re-apply.
local function Remember()
	if original == nil and type(_G.ToggleTalentFrame) == "function" then
		original = _G.ToggleTalentFrame
	end
	return original ~= nil
end

-- What N does while the switch is on. Declared once at load rather than built
-- inside TakeKey, because the pass below runs once a second forever.
local function Toggle()
	ns.TalentWindow.Toggle()
end

local function TakeKey()
	if not Remember() then
		return false
	end
	if _G.ToggleTalentFrame ~= Toggle then
		_G.ToggleTalentFrame = Toggle
	end
	return true
end

-- Only ever hands back what this file took. A client where somebody else is
-- holding the global is a client this file leaves alone.
local function GiveKey()
	if type(original) ~= "function" or _G.ToggleTalentFrame ~= Toggle then
		return false
	end
	_G.ToggleTalentFrame = original
	return true
end

-- What to call the key in a sentence: the first key the client answers, or the
-- letter it ships with where it answers none.
function Blizz.KeyText()
	if type(_G.GetBindingKey) ~= "function" then
		return "N"
	end
	for index = 1, #BINDINGS do
		local key = GetBindingKey(BINDINGS[index])
		if key then
			return key
		end
	end
	return "N"
end

--------------------------------------------------------------------------
-- The frames
--------------------------------------------------------------------------

-- Whether the client's window should be out of the way right now. Two things
-- and no third: our window has to be built at all, and the switch has to be on.
function Blizz.Wanted()
	return (ns.db.talents and ns.db.hideBlizzTalents) and true or false
end

-- Run on every pass rather than only where the answer changed, which is the
-- rule UnitFrames/Blizzard.lua's header argues for at length: a pass that
-- remembers what it did cannot see a frame the client built since.
function Blizz.Apply()
	local wanted = Blizz.Wanted()
	if wanted then
		TakeKey()
	else
		GiveKey()
	end

	local complete = true
	local act = wanted and ns.Attic.Vanish or ns.Attic.Return
	for index = 1, #FRAMES do
		local frame = Frame(FRAMES[index])
		if frame and not act(frame) then
			complete = false
		end
	end
	return complete
end

-- Whether the client's frame is in the attic right now, or would be the moment
-- it existed.
function Blizz.Caged()
	for index = 1, #FRAMES do
		local frame = Frame(FRAMES[index])
		if frame then
			return ns.Attic.Held(frame)
		end
	end
	return Blizz.Wanted() and _G.ToggleTalentFrame == Toggle
end

function Blizz.Describe()
	if not ns.db.hideBlizzTalents then
		return "on screen, and " .. Blizz.KeyText() .. " opens it"
	end
	if not ns.db.talents then
		return "on screen, because this addon's own window is off"
	end
	if type(original) ~= "function" then
		return "never loaded, and this client has no ToggleTalentFrame to redirect"
	end
	return ("never loaded, and %s opens this one"):format(Blizz.KeyText())
end

--------------------------------------------------------------------------

-- The frame arriving after login, caged the moment it does.
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("ADDON_LOADED")
watcher:SetScript("OnEvent", function(_, _, name)
	if name == LOADS and ns.db then
		Blizz.Apply()
	end
end)

-- Registered with the switch it belongs to, so `/wk hide talents`, the panel's
-- own line and `/wk reset` all reach this file without any of them naming it.
ns.BlizzHide.Also(Blizz.Apply)
