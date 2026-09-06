local ADDON, ns = ...

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
-- in Core/BlizzHide.lua, and this file registers into it the way the
-- character sheet's does.
--------------------------------------------------------------------------

-- The window on the newer client and the one the oldest client called it.
-- Every name is probed before it is touched, and a name this client does not
-- carry costs one lookup against nil.
local FRAMES = {
	"PlayerTalentFrame",
	"TalentFrame",
}

-- What N does while the switch is on. A named function at file scope rather
-- than a closure made at the swap, because the swap runs on a pass that goes
-- once a second forever.
local function Toggle()
	ns.TalentWindow.Toggle()
end

-- The mechanism is Core/BlizzAdapter.lua's cage shape, which the quest log's,
-- the map's, the sheet's and the book's use as well. Everything above is why
-- this frame is on that shape rather than the park one, and what is left for
-- this file to say is which frames, which switch, and what N does instead.
--
-- No `bind`, for the reason above: there is no secure button here for an
-- override binding to land on. The binding names stay because the switch's own
-- line names the key that opens this window, and two of them because the two
-- clients disagree about what it is filed under.
--
-- `held` and "never loaded" are the same fact twice: the frame is usually never
-- built, so the flag a cage would set says nothing and the global standing in
-- for it is the next best answer there is. `loads` is the other half, for the
-- evening a second addon pulls Blizzard_TalentUI in for reasons of its own.
ns.TalentBlizzard = ns.BlizzAdapter.Cage({
	frames = FRAMES,
	feature = "talents",
	switch = "hideBlizzTalents",
	global = "ToggleTalentFrame",
	Toggle = Toggle,
	bindings = { "TOGGLETALENTS", "TOGGLETALENTFRAME" },
	fallback = "N",
	pass = true,
	held = true,
	loads = "Blizzard_TalentUI",
	place = "never loaded",
	off = "on screen, because this addon's own window is off",
})
