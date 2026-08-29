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
local since = 0

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
-- The one line this part writes itself is the hint, because a tooltip that
-- follows your pointer around the world is the most annoying thing in the addon
-- if you did not want it, and it owes you the sentence that turns it off.
local function Subject()
	return {
		kind = "unit",
		unit = UNIT,
		title = UnitName(UNIT),
		hint = "/wk world off puts the client's own tooltip back.",
	}
end

function World.Wanted()
	return ns.db.worldTips == true
end

-- Hidden, so nothing runs on an ordinary frame. Shown for as long as a box is
-- on screen and taken down with it.
local ticker = CreateFrame("Frame")
ticker:Hide()

function World.Close()
	if not open then
		return false
	end
	open, since = false, 0
	ticker:Hide()
	ns.UI.Scan.Suppress(false)
	ns.Tip.Close()
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
	if not ns.Tip.Open(ns.UI.Tooltip.CURSOR, Subject()) then
		World.Close()
		return false
	end

	open, since = true, 0
	suppressed = ns.UI.Scan.Suppress(true)
	ticker:Show()
	return true
end

function World.Sweep(elapsed)
	since = since + elapsed
	if since < STEP then
		return
	end
	since = 0
	if not UnitExists(UNIT) then
		World.Close()
	end
end

ticker:SetScript("OnUpdate", function(_, elapsed)
	World.Sweep(elapsed)
end)

-- The setting, acted on. Closing on the way off is the whole reason this exists
-- rather than a write: a box already on screen when the setting goes off would
-- sit there until the next hover, describing a mob under a hint line offering
-- to do the thing you just did.
--
-- The panel writes the boolean itself and calls this; the slash word and the
-- reset go through Set, which writes and then calls this. Two doors and one
-- room, which is the shape every switch in the addon has.
function World.Apply()
	if not World.Wanted() then
		World.Close()
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
		World.Close()
	end
end)
