local ADDON, ns = ...

--------------------------------------------------------------------------
-- Blizzard's socketing frame, out of the way
--
-- The same shape as Merchant/Blizzard.lua and for the same reason, so this
-- header writes down only what is different here.
--
-- **It is parked, not hidden, and not caged.** The client's socketing window is
-- the visible end of a session held on the server, and FrameXML's own handler
-- on that frame calls CloseSocketInfo the moment it stops being drawn. So both
-- of the mechanisms the rest of the addon uses would end the session: ns.Strip
-- begins by calling Hide, and Core/Attic.lua re-parents into a hidden room,
-- which takes the frame's visibility away and fires the same handler. Either
-- one would shut the conversation a frame after opening it, and the symptom
-- would be a window of ours with three empty holes in it.
--
-- What is left is to move it, at no opacity, off the right hand edge, and to
-- put it back there whenever the client relays its panels out.
--
-- **It arrives late.** ItemSocketingFrame is built by Blizzard_ItemSocketingUI,
-- an addon of Blizzard's own that is loaded the first time a session opens, so
-- there is nothing to park at login and nothing to park until the first gem you
-- ever try. The `loads` line below puts an ADDON_LOADED watch on that addon,
-- which is what catches it, and Sockets/Window.lua parks again on its own first
-- paint, because the client shows that frame in the same event handler that
-- loads it.
--
-- **A parked frame is still running, and here that is worth having.** The
-- client raises two confirmations of its own during a socketing session, one
-- for a gem that would bind an unbound item to you and one for an item bought
-- with honour that would stop being refundable, and both are put up by that
-- frame's own event handler. A frame off the side of the screen still gets
-- those events and the popups it raises are frames of their own, in the middle
-- of the screen where they belong. Caging it would have taken both away, and
-- what a player would see is socketing that does nothing.
--
-- **The switch only bites while our window is up.** A session with our window
-- switched off is a session with nothing else to look at, so the park is
-- wanted only when there is a replacement on the screen.
--------------------------------------------------------------------------

-- The mechanism is Core/BlizzAdapter.lua's park shape, which the mailbox's and
-- the merchant's use as well. Everything above is why this frame is on that
-- shape rather than the cage one, and what is left for this file to say is
-- which frame, which switch, that it is walked, and that it arrives late.
--
-- The number the park moves it by is the merchant's, because it is the same
-- question about a frame of about the same width.
ns.SocketBlizzard = ns.BlizzAdapter.Park({
	frame = "ItemSocketingFrame",
	feature = "sockets",
	switch = "socketsHideBlizz",
	window = "SocketWindow",
	pass = true,
	loads = "Blizzard_ItemSocketingUI",
	late = "never loaded yet",
})
