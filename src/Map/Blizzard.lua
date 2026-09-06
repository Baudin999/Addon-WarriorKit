local ADDON, ns = ...

--------------------------------------------------------------------------
-- Blizzard's world map, out of the way
--
-- The same shape as Quests/Blizzard.lua, and for the same two reasons, so this
-- header only writes down where the two differ.
--
-- **The frame goes in the attic.** Nothing about the world map is a live
-- session with the server, the way a mailbox is: every map call works with the
-- frame nowhere near the screen, so it is re-parented into a room that is
-- hidden rather than argued with one Show at a time. Core/Attic.lua carries
-- that argument in full.
--
-- **The M key comes with it.** A hidden map with the key still bound to the
-- client's own toggle is a map you cannot open, which is worse than either
-- window on its own. ToggleWorldMap is a plain global on both of these
-- clients, and the button on the minimap calls it too, so replacing it takes
-- the key and the button in one move. The original is kept so the switch can
-- hand it back exactly.
--
-- **Questie keeps working, and that is the part worth stating.** Questie draws
-- its markers by making a frame per marker and handing it to HereBeDragons to
-- place on the client's map. Caging the client's map means those frames are
-- never placed on anything and never drawn. It does not mean they stop
-- existing: Questie makes them when your log changes and unmakes them when a
-- quest is done, neither of which has anything to do with whether a map is on
-- screen. Map/Pins.lua reads the frames rather than the picture, which is why
-- the markers survive the cage.
--
-- **The switch is `hide Blizzard's world map`.** Off, both maps work and the
-- key opens theirs, which is worth having while anything here is unconfirmed
-- in game: everything this window cannot do, the client's can, and it is one
-- tick box away.
--------------------------------------------------------------------------

-- The frames that make up the client's map. WorldMapFrame is the window;
-- WorldMapTooltip is the box it opens over itself, which is a frame of its own
-- on the builds that have one and absent on the builds that do not. Every name
-- is probed before it is touched, the same as the quest log's furniture list.
local FRAMES = {
	"WorldMapFrame",
	"WorldMapTooltip",
}

-- What the key does while this addon holds it. A named function at file scope
-- rather than a closure made at the swap, because the swap is on a pass that
-- runs once a second and a fresh closure a second is garbage the collector has
-- to walk. It is also what makes "are we already holding it" a comparison.
--
-- **Inside a dungeon it opens the other window.** There is no world map of a
-- dungeon on either of these clients: the 1.15 client has no instance in its
-- map tree at all, and the 2.5 client has the nodes and ships art for not one
-- of them, which Dungeons/Places.lua carries in full. So M pressed at the
-- bottom of Blackrock Depths opened a window that could only draw the continent
-- overhead, which is the one place you already know you are not.
--
-- The adventure guide has the picture. It is drawn from the same tiles
-- Blizzard's own map used to, it knows which floor you are on, and it puts the
-- bosses and what they drop down either side of it. That is what M is for
-- underground. Above ground nothing changes.
local function Ours()
	if ns.db.dungeons and ns.DungeonHere.Dungeon() then
		ns.DungeonWindow.Toggle()
		return
	end
	ns.MapWindow.Toggle()
end

-- The mechanism is Core/BlizzAdapter.lua's cage shape, which the quest log's,
-- the sheet's, the book's and the talent window's use as well. Everything above
-- is why this frame is on that shape rather than the park one, and what is left
-- for this file to say is which frames, which switch, and what M does instead.
--
-- **On the once-a-second walk, and that is not a nicety.** WorldMapFrame is
-- behind a load-on-demand addon on some of these builds, so at PLAYER_LOGIN
-- there may be nothing to cage and a one-shot apply would leave the client's map
-- on the screen for the session. WorldMapTooltip does not exist on every build
-- at all. Both are the case the walk exists for, and everything it does is a
-- comparison once it has taken: the strip is a flag on the frame, the cage is a
-- parent test, and the key is a function identity.
--
-- M is spelled out rather than read off the client, because this part has never
-- taken an override binding and has nothing to name a key with.
ns.MapBlizzard = ns.BlizzAdapter.Cage({
	frames = FRAMES,
	feature = "worldMap",
	switch = "worldMapHideBlizz",
	global = "ToggleWorldMap",
	Toggle = Ours,
	place = "in the attic",
	offKey = "M",
	onKey = "M",
	pass = true,
})
