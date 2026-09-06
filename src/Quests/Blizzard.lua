local ADDON, ns = ...

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

-- What L does while the switch is on. A named function at file scope rather
-- than a closure made at the swap, which is what makes "are we already holding
-- it" a comparison.
local function Toggle()
	ns.QuestWindow.Toggle()
end

-- The mechanism is Core/BlizzAdapter.lua's cage shape, which the map's, the
-- sheet's, the book's and the talent window's use as well. Everything above is
-- why this frame is on that shape rather than the park one, and what is left
-- for this file to say is which frames, which switch, and what L does instead.
--
-- **Off the once-a-second walk.** The log is not a frame the client rebuilds
-- underneath us and there is no load-on-demand addon behind it, so the cage is
-- applied when the switch moves. Quests/Feature.lua and Quests/Window.lua are
-- what call it.
--
-- L is spelled out rather than read off the client, because this part has never
-- taken an override binding and has nothing to name a key with.
ns.QuestBlizzard = ns.BlizzAdapter.Cage({
	frames = FRAMES,
	feature = "quests",
	switch = "questsHideBlizz",
	global = "ToggleQuestLog",
	Toggle = Toggle,
	place = "in the attic",
	offKey = "L",
	onKey = "L",
})
