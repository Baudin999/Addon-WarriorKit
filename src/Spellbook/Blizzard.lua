local ADDON, ns = ...

--------------------------------------------------------------------------
-- Blizzard's spell book, out of the way
--
-- One frame and one key, and the argument for both is the character sheet's.
-- SpellBookFrame is not a live server session the way the mail window is:
-- every call this addon makes about your spells, reading the book and
-- picking a rank up included, works with that frame nowhere near the screen.
-- So it goes in the attic, where a hidden parent beats every route the client
-- has to put a frame back, rather than being parked off the side where a
-- relayout could return it.
--
-- Your pet's book goes with it, because it is a page of the same frame. This
-- addon does not draw one, and that is said in the switch's own hint rather
-- than worked around: the honest answer to a page a warrior never opens is a
-- sentence and a tick box.
--
-- **The key has to come with it.** Hiding the window and leaving P bound to
-- the client's own toggle is a spell book you cannot open, which is worse
-- than either window on its own. ToggleSpellBook is a plain global on both of
-- these clients and it carries which book it meant, so it is replaced with
-- one that opens this addon's window for the spell book and says so for the
-- pet's, and the original is kept so the switch can hand it back exactly.
--
-- The key goes onto a secure button as well as onto the global, for the
-- reason the character sheet's does: every square on the window is a secure
-- button, showing a window with one inside it is protected, and only a
-- snippet may do that in a fight. An override binding onto the window's key
-- button is that snippet's doorbell.
--
-- **The switch is the one on the Blizzard page.** There is one place in this
-- addon where a frame of the client's is switched on or off, it is the list
-- in Core/BlizzHide.lua, and this file registers into it the way the
-- character sheet's and the talent window's do.
--------------------------------------------------------------------------

local FRAMES = {
	"SpellBookFrame",
}

-- The book the client's toggle is asked for when it means your pet's.
local PET = "pet"

-- What P does while the switch is on. Declared once at load rather than
-- built at the swap, because the pass this file signs into below runs once a
-- second forever.
local function Toggle(bookType)
	if bookType == PET then
		ns.Print("this window does not draw your pet's book. Untick hiding Blizzard's spell book to get it back.")
		return
	end
	ns.SpellWindow.Toggle()
end

-- The mechanism is Core/BlizzAdapter.lua's cage shape, which the sheet's, the
-- talent window's, the quest log's and the map's use as well. Everything above
-- is why this frame is on that shape rather than the park one, and what is left
-- for this file to say is which frame, which switch, and what P does instead.
--
-- `bind` is the half the quest log and the map do not take, and the header says
-- why: every square on this window is a secure button, so the press has to reach
-- a snippet rather than the plain global. Spellbook/Window.lua owns the button
-- the binding lands on, which is what `window` names.
ns.BookBlizzard = ns.BlizzAdapter.Cage({
	frames = FRAMES,
	feature = "spellbook",
	switch = "hideBlizzSpellbook",
	global = "ToggleSpellBook",
	Toggle = Toggle,
	bindings = { "TOGGLESPELLBOOK" },
	fallback = "P",
	bind = true,
	window = "SpellWindow",
	pass = true,
	held = true,
	place = "in the attic",
	off = "on screen, because this addon's own book is off",
})
