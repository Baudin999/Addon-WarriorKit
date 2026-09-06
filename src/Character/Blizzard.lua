local ADDON, ns = ...

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

-- What C does while the switch is on. Declared once at load rather than built
-- at the swap, and that is not tidiness: the pass this file signs into below
-- runs once a second forever, and a closure made on every pass is a function
-- object a second for the collector to walk. It was three kilobytes per fifty
-- ticks and the harness's allocation gate caught it.
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

-- The mechanism is Core/BlizzAdapter.lua's cage shape, which the book's, the
-- talent window's, the quest log's and the map's use as well. Everything above
-- is why these frames are on that shape rather than the park one, and what is
-- left for this file to say is which frames, which switch, and what C does
-- instead.
--
-- `bind` is the half the quest log and the map do not take: the gear page is
-- secure buttons, showing a window with one inside it is protected, and only a
-- snippet may do that in a fight. Character/Window.lua owns the button the
-- override binding lands on, which is what `window` names.
--
-- `offKey` is the letter rather than the key the client answers, and it is the
-- one place this part's wording differs from the book's and the talent
-- window's. With the switch off nothing here is holding a key, so the sentence
-- is about the client's own binding and this file has never claimed to have
-- read it. The key the switch names with the switch on is read, because by then
-- it is a key this part took.
ns.CharBlizzard = ns.BlizzAdapter.Cage({
	frames = FRAMES,
	feature = "character",
	switch = "hideBlizzCharacter",
	global = "ToggleCharacter",
	Toggle = Toggle,
	bindings = { "TOGGLECHARACTER0", "TOGGLECHARACTER" },
	fallback = "C",
	bind = true,
	window = "CharWindow",
	pass = true,
	held = true,
	place = "in the attic",
	off = "on screen, because this addon's own sheet is off",
	offKey = "C",
})
