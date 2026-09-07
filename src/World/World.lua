local ADDON, ns = ...

local World = {}
ns.World = World

--------------------------------------------------------------------------
-- The hover no frame in this addon owns
--
-- Every other hover in WarriorKit is answered by the thing under the cursor. A
-- feed row, a nag square, an action slot and a filter chip all have an OnEnter,
-- and UI/Tip.lua replaces what they would have said. A creature in the 3D world
-- has none of that. The cursor is over WorldFrame, the client resolves the
-- `mouseover` token by itself, fills its own tooltip by itself and shows it by
-- itself, and there is no script anywhere in that sequence for an addon to
-- write. The same is true of a nameplate: UnitFrames/EnemyBars.lua calls
-- EnableMouse(false) on its bar precisely so the plate underneath keeps the
-- click, so the frame the pointer is actually over is Blizzard's, not ours.
--
-- So this part is built the other way round from the rest of the addon. It does
-- not intercept a hover; it hears that one happened, opens the addon's own box
-- for it, and asks UI/Scan.lua to hold the client's box down for as long as
-- ours is up. Two halves, and the second is the one with the sharp edge: the
-- reasoning for how narrowly Blizzard's tooltip is hidden, and what a player
-- loses if that goes wrong, is written where the code is, in UI/Scan.lua.
--
-- **Any mouseover, not only one in the world.** A unit frame sets the token
-- too, and this opens for those as well, which is exactly what the client does
-- and is why no test on the mouse focus is worth writing. The one seam it
-- leaves is the aura squares under the skinned target block: hovering one opens
-- its own box over this one, and leaving it closes both, so the unit's box does
-- not come back until the pointer finds a different unit. That is a smaller
-- wrong than a tooltip that guesses which frames belong to whom.
--
-- **The event says when a hover begins and not when it ends.**
-- UPDATE_MOUSEOVER_UNIT fires when the token resolves to somebody new. Nothing
-- fires reliably when the pointer slides off onto empty ground, and a box that
-- opens on a mob and stays there after you have looked away is worse than no
-- box. So there is a ticker, it runs only while the box is on screen, and the
-- one question it asks is whether the mouseover still exists.
--------------------------------------------------------------------------

local UNIT = "mouseover"

-- A tenth of a second, which is the same step the enemy bars run at. It is the
-- delay between looking away and the box going, and anything shorter is asking
-- UnitExists more often than a person can notice.
local STEP = 0.1

local open = false

-- The mob the box on screen is about.
--
-- UPDATE_MOUSEOVER_UNIT does not fire once per hover. It fires whenever the
-- token resolves, which a moving mob, a moving camera and a mob that dies and
-- leaves a corpse under your pointer all do again for the same creature, and
-- each one built the whole box a second time: a unit scan of Blizzard's tooltip,
-- every band laid out again and the suppression armed on top of the box it was
-- already holding down. The same guid is the same box.
local looking

-- Whether the last arm of the suppression actually took, for Describe. Nil
-- until the first hover, because "not tried yet" and "this client refused" are
-- different things to tell a player.
local suppressed

-- What the addon has to say about the thing under the cursor.
--
-- The head band is the client's own lines about the unit, which are already
-- right and already localised, and the extra band is whatever other parts
-- registered against the kind. The title is the fallback under that, the way it
-- is on every item hover in the addon: a client with no SetUnit answers no
-- lines at all, and a box carrying a threat reading over an unnamed thing is
-- worse than a box carrying a name.
--
-- No hint line. The box follows your pointer around the world, so a standing
-- footnote about the switch that turns it off is on screen the whole time you
-- are playing, and the panel and the slash word both already say it.
local function Subject()
	return {
		kind = "unit",
		unit = UNIT,
		title = UnitName(UNIT),
	}
end

function World.Wanted()
	return ns.db.worldTips == true
end

-- Whether the box on screen is the one this file put there.
--
-- **The addon has one tooltip and every hover in it draws in that one frame.**
-- A bag square, a unit frame, a feed row: each of them opens the same box on
-- itself and takes it down again on the way out, and none of them tells this
-- file that it did. So "our box is up" is not something this file may remember.
-- It is something it has to ask, and the two calls below are the whole of the
-- question.
--
-- Owner rather than IsShown alone, because a box counted down by the linger is
-- still shown and belongs to nobody: UI/Tip.lua drops the owner the moment the
-- pointer leaves what it was describing.
local function Ours()
	local Box = ns.UI.Tooltip
	return Box.IsShown() and Box.Owner() == Box.CURSOR
end

-- Hidden, so nothing runs on an ordinary frame. Shown for as long as a box is
-- on screen and taken down with it.
local ticker = CreateFrame("Frame")
ticker:Hide()

-- `now` takes the box down on the spot rather than letting it linger. Two
-- callers pass it and both are the same case: the mob is not something you
-- looked away from, it is something that is no longer there at all. A loading
-- screen puts a zone between you and it, and the setting going off means the
-- addon is not describing mobs any more. A second of a sentence about either is
-- a second of a sentence about nothing.
-- **And the box goes only if it is still ours.** Every other line here is this
-- file's own state and is put back whatever is on screen, but the last one
-- reaches into the frame every hover in the addon shares. A creature that stops
-- existing while the pointer is over a bag square is this state coming down and
-- somebody else's tooltip staying up, and the hover record inside UI/Tip.lua is
-- already theirs by then: closing on their behalf would take down a box the
-- player is reading and leave nothing to say why.
function World.Close(now)
	if not open then
		return false
	end
	local ours = Ours()
	open = false
	looking = nil
	ticker:Hide()
	ns.UI.Scan.Suppress(false)
	if ours then
		ns.Tip.Close(now)
	end
	return true
end

-- Open on whatever the token resolves to.
--
-- The suppression is armed after the box is up rather than before, and a refusal
-- closes rather than returning. Tip.Open refuses a subject with nothing in any
-- band, which is what a client that answers nothing about a unit produces, and
-- the state to avoid is the suppression armed with no box of our own on screen:
-- that is Blizzard's tooltip held down in exchange for nothing. Failing back to
-- the client's own box is the right way round to fail.
function World.Open()
	if not World.Wanted() or not UnitExists(UNIT) then
		return false
	end
	-- The same creature again, with our box already up for it. One call to find
	-- that out against the whole build.
	--
	-- **And our box rather than a box**, which is the second test and is the
	-- whole of what this refusal used to get wrong. A hover crossed on the way
	-- past takes the frame over and takes it down again when you leave it, so
	-- this file's `open` says what it last did rather than what is on screen.
	-- Believing it left the creature under the pointer with no box of ours, no
	-- event on its way to say so, and the suppression still holding Blizzard's
	-- box down: a mob you were pointing straight at with no tooltip of any kind.
	local guid = UnitGUID(UNIT)
	if open and guid and guid == looking and Ours() then
		return true
	end
	if not ns.Tip.Open(ns.UI.Tooltip.CURSOR, Subject()) then
		World.Close()
		return false
	end

	open = true
	looking = guid
	suppressed = ns.UI.Scan.Suppress(true)
	ticker:Show()
	return true
end

-- The box was taken over by a hover that owns a frame.
--
-- Everything World.Close does bar the one thing it must not do here: the box on
-- screen is somebody else's now, and closing it would take down the tooltip of
-- whatever the pointer actually moved onto. The suppression comes off, because
-- it is armed only in exchange for a box of ours being up and there is no
-- longer one, and this file goes back to believing nothing. The next time the
-- token resolves, which for a live creature is the next time it or the camera
-- moves, World.Open builds the box again rather than refusing as a repeat.
local function Yield()
	open = false
	looking = nil
	ticker:Hide()
	ns.UI.Scan.Suppress(false)
	return true
end

-- One pass, and it asks two questions rather than one.
--
-- The token going away is the pointer leaving the creature, and that closes.
-- The box no longer being ours is another hover crossing over this one, and
-- that yields. Both used to be one question, and the second was not asked at
-- all.
function World.Sweep()
	if not UnitExists(UNIT) then
		return World.Close()
	end
	if Ours() then
		return false
	end
	return Yield()
end

ns.UI.Ticker(ticker, STEP, "world", World.Sweep)

-- The setting, acted on. Closing on the way off is the whole reason this exists
-- rather than a write: a box already on screen when the setting goes off would
-- sit there until the next hover, describing a mob you are no longer asking
-- about.
--
-- The panel writes the boolean itself and calls this; the slash word and the
-- reset go through Set, which writes and then calls this. Two doors and one
-- room, which is the shape every switch in the addon has.
function World.Apply()
	if not World.Wanted() then
		World.Close(true)
	end
	return World.Wanted()
end

function World.Set(on)
	ns.db.worldTips = on and true or false
	return World.Apply()
end

-- What the player would see, rather than what this file meant to do. The middle
-- two answers are the ones worth having: both are a client refusing something,
-- both leave the addon looking broken, and neither says anything on its own.
function World.Describe()
	if not World.Wanted() then
		return "off, and the client draws its own"
	end
	if not ns.UI.Scan.Ready("unit") then
		return "on, but this client hands over no text about a unit, so a hover shows the name and nothing more"
	end
	if suppressed == false then
		return "on, but this client would not let the addon hold Blizzard's box down, so a mob is described twice"
	end
	return "on, in the addon's own box"
end

local events = CreateFrame("Frame")
events:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
-- A loading screen stops every OnUpdate in the client, so the ticker cannot
-- notice that the mob it was watching is a zone away. Without this the box
-- would still be on screen at the other end.
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function(_, event)
	if event == "UPDATE_MOUSEOVER_UNIT" and UnitExists(UNIT) then
		World.Open()
	else
		World.Close(event == "PLAYER_ENTERING_WORLD")
	end
end)
