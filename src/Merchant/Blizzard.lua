local ADDON, ns = ...

--------------------------------------------------------------------------
-- Blizzard's merchant window, out of the way
--
-- The same shape as Mail/Blizzard.lua, and for the same reason, so this header
-- only writes down where the two differ and why the reason matters more here.
--
-- **It is parked, not hidden, and not caged.** MerchantFrame is not an ordinary
-- window. Standing at a vendor is a live interaction with the server, and the
-- client ends it when that frame stops being drawn: FrameXML's own handler on
-- the frame calls CloseMerchant, which is why walking out of range and pressing
-- escape both do the same thing. So the two mechanisms the rest of the addon
-- uses are both wrong here, and each is wrong in a way that looks like it works.
--
-- ns.Strip puts a region's own Hide where its Show was, and its first act is to
-- call Hide. That is the session going down.
--
-- Core/Attic.lua re-parents a frame into a room that is hidden, which is the
-- stronger guarantee everywhere else precisely because nothing the client does
-- can put the frame back on the screen. Here it is the wrong one for the same
-- reason it is wrong for the mailbox: visibility in this client is a property
-- of the parent chain, a frame whose parent is hidden stops being visible, and
-- stopping being visible is exactly what the frame's own handler reacts to. The
-- attic would close the merchant a frame after opening it, and the symptom
-- would be a window of ours with an empty rack in it.
--
-- What is left is to move it. The frame stays shown and stays parented to
-- UIParent, so the session stays up and every merchant call goes on working; it
-- is put off the side of the screen at no opacity, so it draws nothing and its
-- buttons are nowhere a cursor can reach them.
--
-- That last clause is what makes MerchantWindow.Leave load bearing. The client's
-- cross is the thing that would normally end a session and it is now off the
-- screen, so this addon's window has to end it instead, and it does, on the
-- frame's own OnHide.
--
-- **Why it has to be re-parked.** MerchantFrame is a UIPanel and the client
-- lays the panels out again whenever one opens or closes, which puts it back in
-- the middle of the screen. Opening your own bags at a vendor is enough to do
-- it. So the park is re-applied on the frame's own OnShow, through HookScript
-- rather than SetScript, because the handler already there is the client's.
--
-- **Comfort/Vendor.lua goes on working untouched, and that is not luck.** It
-- asks MerchantFrame:IsShown() before every sweep, because the call that sells
-- a bag slot *uses* it when no merchant is up. A parked frame is still shown:
-- what changed is where it is and what alpha it is drawn at, neither of which
-- that guard reads. Caging it would have kept IsShown true as well and closed
-- the session underneath, which is the failure that would have passed review.
--
-- **The switch is `hide Blizzard's merchant window`.** Off, both windows are up
-- and ours is the one in front, which is worth having while anything here is
-- unconfirmed in game: everything this addon's window cannot do, the client's
-- can, and it is one tick box away.
--------------------------------------------------------------------------

-- The mechanism is Core/BlizzAdapter.lua's park shape, which the mailbox's and
-- the socketing window's use as well. Everything above is why this frame is on
-- that shape rather than the cage one, and what is left for this file to say is
-- which frame, which switch, and that it is walked.
--
-- **On the once-a-second walk.** The client relays its panels out whenever one
-- opens, and opening your own bags at a vendor is enough to do it, so a park
-- applied only when the switch moves is a park that lasts until the next time
-- you open your bags. The walk is also where the drift correction runs, which
-- is two reads on a frame that has not moved.
ns.MerchantBlizzard = ns.BlizzAdapter.Park({
	frame = "MerchantFrame",
	feature = "merchant",
	switch = "merchantHideBlizz",
	window = "MerchantWindow",
	pass = true,
})
