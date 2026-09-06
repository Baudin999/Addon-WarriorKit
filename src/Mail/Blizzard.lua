local ADDON, ns = ...

--------------------------------------------------------------------------
-- Blizzard's mail window, out of the way
--
-- **It is parked, not hidden, and that distinction is the whole file.**
--
-- MailFrame is not an ordinary window. The mailbox is a live interaction with
-- the server, and the client ends it when that frame stops being drawn:
-- TitanPost secure-hooks MailFrame_Hide for exactly that signal, which is how
-- you know hiding is the thing that closes the mailbox rather than a
-- consequence of it. The client's own MAIL_SHOW handler makes the same point
-- from the other side, calling CloseMail when ShowUIPanel could not find room
-- for the frame.
--
-- So this part uses neither of the two mechanisms the rest of the addon uses,
-- and the next person to read this file will want to change that. Both would
-- close the mailbox.
--
-- ns.Strip puts a region's own Hide where its Show was, and its first act is to
-- call Hide. That is the frame going down.
--
-- Core/Attic.lua re-parents a frame into a room that is hidden, which is the
-- better mechanism everywhere else precisely because nothing the client does
-- can put the frame back on the screen. Here it is the wrong one for the same
-- reason: visibility in this client is a property of the parent chain, a frame
-- whose parent is hidden stops being visible, and stopping being visible is
-- what MailFrame's own handler reacts to. The attic is a stronger guarantee
-- than parking and this is the one frame that must not have it.
--
-- What is left is to move it. The frame stays shown and stays parented to
-- UIParent, so the interaction stays up and every mail API goes on working; it
-- is put off the side of the screen at no opacity, so it draws nothing and its
-- buttons are nowhere a cursor can reach them. Every one of those is reversible
-- in one call and none of them touches the frame's shown state or its parent.
--
-- The cost against the attic is honest and is why this is not the default
-- anywhere else: a client that repositions the frame between our re-parks puts
-- it back on the screen, where the attic could not. That failure is visible
-- rather than silent, and `/wk mail hide off` is the way out of it.
--
-- **Why it has to be re-parked.** MailFrame is a UIPanel and the client lays
-- the panels out again whenever one opens or closes, which puts it back in the
-- middle of the screen. So the park is re-applied on the frame's own OnShow,
-- through HookScript rather than SetScript, because the handler already there
-- is the client's and taking it off would be taking the mailbox with it.
--
-- **The switch is `hide Blizzard's mail window`.** Off, both windows are up and
-- ours is the one in front, which is worth having while anything here is still
-- unconfirmed in game: everything this addon's window cannot do, the client's
-- can, and it is one tick box away.
--------------------------------------------------------------------------

-- The mechanism is Core/BlizzAdapter.lua's park shape, which the merchant's and
-- the socketing window's use as well. Everything above is why this frame is on
-- that shape rather than the cage one, and the only thing this file has to say
-- besides is which frame and which switch.
--
-- **Off the once-a-second walk, unlike the other two.** The mailbox is opened by
-- standing at one, and the window is closed by the part's own code rather than
-- by the client relaying its panels underneath it, so the park is applied when
-- the switch moves and answers whether it moved anything. Mail/Window.lua and
-- Mail/Feature.lua are what call it.
ns.MailBlizzard = ns.BlizzAdapter.Park({
	frame = "MailFrame",
	feature = "mail",
	switch = "mailHideBlizz",
	window = "MailWindow",
})
