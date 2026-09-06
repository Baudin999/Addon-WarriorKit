local ADDON, ns = ...

local Blizz = {}
ns.CharBlizzard = Blizz

--------------------------------------------------------------------------
-- Blizzard's character sheet, out of the way
--
-- One frame and one key, and the argument for both is the quest log's.
-- CharacterFrame is not a live server session the way the mail window is:
-- every call this addon makes about your gear, your skills and your standings
-- works with that frame nowhere near the screen. So it goes in the attic, where
-- a hidden parent beats every route the client has to put a frame back, rather
-- than being parked off the side where a relayout could return it.
--
-- Its five pages go with it because all five are its children. Two of those
-- five this addon does not draw: the pet sheet and the honour tab. That is said
-- in the switch's own hint rather than worked around, because the honest answer
-- to two pages nobody opens twice a month is one sentence and a tick box, not a
-- sixth tab written against an API this addon has no other reason to learn.
--
-- **The key has to come with it.** Hiding the window and leaving C bound to the
-- client's own toggle is a character sheet you cannot open, which is worse than
-- either window on its own. ToggleCharacter is a plain global on both of these
-- clients and it carries which page it meant, so it is replaced with one that
-- opens the addon's window for that page, and the original is kept so the
-- switch can hand it back exactly.
--
-- That is the second global function swap in the addon, after the quest log's,
-- and it is here for the same reason: one file, named after the frame it is
-- doing it to.
--
-- **The switch is the one on the Blizzard page.** It is not a setting of its
-- own on the character part's page, and that is deliberate: there is one place
-- in this addon where a frame of the client's is switched on or off, it is the
-- list in Core/BlizzHide.lua, and a tenth switch that lived somewhere else
-- would be the tenth place somebody has to look.
--------------------------------------------------------------------------

-- The window and the two pages the client keeps outside it. Every name is
-- probed before it is touched: PetPaperDollFrame is a child on both of these
-- clients and is named here anyway, because the attic is idempotent and a name
-- this client does not carry costs one lookup against nil.
local FRAMES = {
	"CharacterFrame",
	"PaperDollFrame",
	"SkillFrame",
	"ReputationFrame",
	"PetPaperDollFrame",
	"HonorFrame",
}

-- Which window the client's own page name opens.
--
-- It was a tab number each. There are no tabs now: the gear and the skills are
-- one page, so two of these three land on the same window, and the standings
-- have a window of their own. The two names that answer nothing are the two
-- this addon does not draw, and they get a sentence below rather than an entry
-- here.
local PAGES = {
	PaperDollFrame = function() ns.CharWindow.Toggle() end,
	SkillFrame = function() ns.CharWindow.Toggle() end,
	ReputationFrame = function() ns.CharRepWindow.Toggle() end,
}

local MISSING = {
	PetPaperDollFrame = "your pet's sheet",
	HonorFrame = "the honour tab",
}

-- What the client's C key called before this addon took it.
local original = nil

-- Whether the secure button's binding needs looking at. True at login and
-- whenever the client says the bindings moved, false once they have been taken.
--
-- A flag rather than a comparison, and that is not tidiness: the pass that calls
-- this runs once a second forever, and asking the client for its keys and
-- joining them into a string on every one of those passes is a string a second
-- for the collector to walk. The harness's allocation gate caught exactly that.
local dirty = true

-- The first key this file is currently holding, or nil where it holds none.
-- Both a flag, for the hand back, and the answer to what the key is called: once
-- an override is on a key the client stops answering that key for the command
-- underneath, so asking again after binding would name the wrong letter.
local bound = nil

-- The client's own binding for its character page. Two names because the two
-- clients this addon runs on do not agree: the numbered one is what a modern
-- Bindings.xml carries and the bare one is the fallback, and a client that has
-- neither leaves the secure button unbound and the global doing the work.
local BINDINGS = { "TOGGLECHARACTER0", "TOGGLECHARACTER" }

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

-- Whoever is holding ToggleCharacter now, remembered once. Called before the
-- swap and never after, so a second addon that wrapped the same global after us
-- is not swallowed by a later re-apply.
local function Remember()
	if original == nil and type(_G.ToggleCharacter) == "function" then
		original = _G.ToggleCharacter
	end
	return original ~= nil
end

-- What C does while the switch is on. Declared once at load rather than built
-- inside TakeKey, and that is not tidiness: the pass below runs once a second
-- forever, and a closure made on every pass is a function object a second for
-- the collector to walk. It was three kilobytes per fifty ticks and the
-- harness's allocation gate caught it.
local function Toggle(page)
	local missing = MISSING[page]
	if missing then
		ns.Print(("this window does not draw %s. Untick hiding Blizzard's character sheet to get it back.")
			:format(missing))
		return
	end
	-- A name this table does not carry is the sheet, which is what the bare key
	-- means and what every caller that passes nothing at all wants.
	local open = PAGES[page] or PAGES.PaperDollFrame
	open()
end

-- Every key the client has on its own character page, in the order it answers
-- them. Called when the bindings have moved and never on the idle pass.
local function Keys()
	local keys = {}
	if type(_G.GetBindingKey) ~= "function" then
		return keys
	end
	for index = 1, #BINDINGS do
		local first, second = GetBindingKey(BINDINGS[index])
		if first then
			keys[#keys + 1] = first
		end
		if second then
			keys[#keys + 1] = second
		end
	end
	return keys
end

-- The key on the secure button as well as on the global.
--
-- The global is what every other caller of ToggleCharacter reaches and it is
-- ordinary Lua, so it cannot show this window in a fight: the sheet has secure
-- buttons on its gear page and showing a window with a protected frame in it is
-- protected. The press itself has to arrive somewhere else, and an override
-- binding onto a secure button is that somewhere: the client sends the press to
-- the button, the button's snippet shows the window, and a snippet is allowed to
-- in combat because a snippet is secure code.
--
-- An override binding rather than SetBinding, because this is a key this addon
-- is borrowing rather than a key the player set: it is not written to their
-- bindings, and clearing it hands the key straight back to whatever they had.
--
-- Refused in lockdown, like every binding call, and the pass that runs once a
-- second and again when combat drops puts it right.
local function Bind()
	if not dirty then
		return true
	end
	if type(_G.SetOverrideBindingClick) ~= "function" then
		return false
	end
	local button = ns.CharWindow.Key()
	if not button or InCombatLockdown() then
		return false
	end
	ClearOverrideBindings(button)
	local keys = Keys()
	for index = 1, #keys do
		SetOverrideBindingClick(button, true, keys[index], ns.CharWindow.KeyName(), "LeftButton")
	end
	dirty, bound = false, keys[1]
	return bound ~= nil
end

local function Unbind()
	if not bound then
		return false
	end
	local button = ns.CharWindow.Key()
	if not button or InCombatLockdown() then
		return false
	end
	ClearOverrideBindings(button)
	dirty, bound = true, nil
	return true
end

-- The client's own binding set moved, so whatever this file took has to be
-- taken again off the new one. The pass does the work; this only says that
-- there is work.
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("UPDATE_BINDINGS")
watcher:SetScript("OnEvent", function()
	dirty = true
end)

local function TakeKey()
	if not Remember() then
		return false
	end
	if _G.ToggleCharacter ~= Toggle then
		_G.ToggleCharacter = Toggle
	end
	return Bind()
end

-- Only ever hands back what this file took. A client where somebody else is
-- holding the global is a client this file leaves alone, which is the same rule
-- Remember keeps at the other end.
local function GiveKey()
	Unbind()
	if type(original) ~= "function" or _G.ToggleCharacter ~= Toggle then
		return false
	end
	_G.ToggleCharacter = original
	return true
end

-- What to call the key in a sentence. The first one the client answers, or the
-- letter it ships with where it answers none, because a line telling somebody to
-- press nothing is worse than a line naming the wrong key.
function Blizz.KeyText()
	if bound then
		return bound
	end
	local keys = Keys()
	return keys[1] or "C"
end

--------------------------------------------------------------------------
-- The frames
--------------------------------------------------------------------------

-- Whether the client's window should be out of the way right now. Two things,
-- and no third: our window has to be built at all, and the switch has to be on.
-- Unlike the chat window's there is no "and ours is open" clause, because the
-- key opens ours, so there is never a moment where the sheet is unreachable.
function Blizz.Wanted()
	return (ns.db.character and ns.db.hideBlizzCharacter) and true or false
end

-- Run on every pass rather than only where the answer changed, which is the
-- rule Core/BlizzHide.lua's header argues for at length: a pass that
-- remembers what it did cannot see a frame the client built since, and cannot
-- see one the client put back by a route the hide did not cover.
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

function Blizz.Describe()
	if not ns.db.hideBlizzCharacter then
		return "on screen, and C opens it"
	end
	if not ns.db.character then
		return "on screen, because this addon's own sheet is off"
	end
	if type(original) ~= "function" then
		return "in the attic, and this client has no ToggleCharacter to redirect"
	end
	return ("in the attic, and %s opens this one"):format(Blizz.KeyText())
end

--------------------------------------------------------------------------

-- Registered with the switch it belongs to, so `/wk hide character`, the
-- panel's own line and `/wk reset` all reach this file without any of them
-- naming it.
ns.BlizzHide.Also(Blizz.Apply)
