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
-- opens the matching tab of this addon's window, and the original is kept so
-- the switch can hand it back exactly.
--
-- That is the second global function swap in the addon, after the quest log's,
-- and it is here for the same reason: one file, named after the frame it is
-- doing it to.
--
-- **The switch is the one on the Blizzard page.** It is not a setting of its
-- own on the character part's page, and that is deliberate: there is one place
-- in this addon where a frame of the client's is switched on or off, it is the
-- list in UnitFrames/Blizzard.lua, and a tenth switch that lived somewhere else
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

-- Which of this window's tabs the client's own page name opens. The two that
-- answer nothing are the two this addon does not draw, and they get a sentence
-- rather than a tab.
local PAGES = {
	PaperDollFrame = 1,
	SkillFrame = 3,
	ReputationFrame = 4,
}

local MISSING = {
	PetPaperDollFrame = "your pet's sheet",
	HonorFrame = "the honour tab",
}

-- What the client's C key called before this addon took it.
local original = nil

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
	ns.CharWindow.Toggle(PAGES[page])
end

local function TakeKey()
	if not Remember() then
		return false
	end
	if _G.ToggleCharacter ~= Toggle then
		_G.ToggleCharacter = Toggle
	end
	return true
end

-- Only ever hands back what this file took. A client where somebody else is
-- holding the global is a client this file leaves alone, which is the same rule
-- Remember keeps at the other end.
local function GiveKey()
	if type(original) ~= "function" or _G.ToggleCharacter ~= Toggle then
		return false
	end
	_G.ToggleCharacter = original
	return true
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
-- rule UnitFrames/Blizzard.lua's header argues for at length: a pass that
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
	return "in the attic, and C opens this one"
end

--------------------------------------------------------------------------

-- Registered with the switch it belongs to, so `/wk hide character`, the
-- panel's own line and `/wk reset` all reach this file without any of them
-- naming it.
ns.BlizzHide.Also(Blizz.Apply)
