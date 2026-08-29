-- The hover no frame in the addon owns
--
-- Every other section that touches a tooltip goes through the thing that opened
-- one: a feed row, a nag square, an action square, all of them frames this addon
-- drew and hung an OnEnter on. A creature in the 3D world is none of those. The
-- cursor is over WorldFrame, the client resolves the mouseover token, fills
-- GameTooltip and shows it, and there is no script in that sequence for an addon
-- to write. So this part is built the other way round and every claim in it is a
-- claim the sections above cannot make.
--
--   The unit kind. UI/Scan.lua points its hidden tooltip at a unit token and
--   reads back the name, the level tag and what the thing is. Those five lines
--   are localised and computed inside the game, and the addon has no other way
--   to word any of them.
--
--   The box with no owner. Everything else takes its position and its zoom from
--   the frame it opened on. This one has neither, so it follows the pointer,
--   picks its side the way a frame's tooltip picks one, and reads the cursor in
--   physical pixels through a UI scale that is not 1.
--
--   The suppression, which is the half with the sharp edge. GameTooltip is
--   shared with quest text, with a link somebody clicked in chat and with every
--   other addon installed, so it is held down only while ours is up and only
--   when it is about a unit. Both halves of that are asserted here, because
--   getting the second wrong is a linked item that silently says nothing.
--
--   The hook, from the other end. Meter/Standing.lua registers one line against
--   the unit kind and never learns that this part exists. That is the whole
--   claim ns.Tip.Source is for and it cannot be made from inside the part that
--   opens the box.

local H = ...
local ns, check, fire = H.ns, H.check, H.fire
local guids, unitName = H.guids, H.unitName
local state, tooltips, cursor = H.state, H.tooltips, H.cursor
local CHURN = H.CHURN

do
	local World, Box = ns.World, ns.UI.Tooltip
	local MOB = "Creature-0-0-0-0-1234-0000ab77"

	-- Every line of the box, left side only. Read off what was drawn rather
	-- than off Tip.Build, because the order things landed in on screen is the
	-- thing being asserted.
	local function drawn()
		local lines = {}
		for index = 1, Box.Lines() do
			lines[index] = Box.Text(index) or ""
		end
		return lines
	end

	-- One edge of the box in physical pixels, which is the unit
	-- GetCursorPosition answers in and the only unit the two can be compared in.
	-- The box is drawn inside a frame on the addon's own grid and the pointer is
	-- read off a screen at a UI scale of 0.65, so a comparison that skipped
	-- either scale would pass against a box anchored to the wrong number.
	local function edge(method)
		local frame = Box.Frame()
		return ns.Measure(frame, method) * frame:GetEffectiveScale()
	end

	-- The pointer in those same pixels. The client answers a y measured up from
	-- the bottom of the screen and every edge above is read from the top left
	-- corner, which is the one conversion in this file and is the same one
	-- UI/Tooltip.lua makes when it anchors the box to UIParent's bottom.
	local function pointer()
		local x, y = _G.GetCursorPosition()
		return x, y - _G.UIParent:GetHeight() * _G.UIParent:GetEffectiveScale()
	end

	-- The client's own words about a mob: the name, the level and rank tag, and
	-- what kind of thing it is. Three lines rather than five because what is
	-- asserted is that they arrive in order and land in the head band, and a
	-- faction and a guild would prove the same thing twice.
	tooltips.unit.mouseover = {
		{ "Snarlmouth" },
		{ "Level 62 Elite", "Beast" },
		{ "Silverpine Forest" },
	}
	unitName.mouseover = "Snarlmouth"

	------------------------------------------------------------------
	-- The scanner will answer about a unit
	------------------------------------------------------------------

	check(ns.UI.Scan.Ready("unit"),
		"the scanner will not take a unit, so a creature can only ever be described by its token")

	local read = ns.UI.Scan.Read("unit", "mouseover")
	check(type(read) == "table" and #read == 3,
		("the client's three lines about a mob came back as %s"):format(tostring(read and #read)))
	check(read[1][1] == "Snarlmouth",
		"the first line is not the name: " .. tostring(read[1][1]))
	check(read[2][5] == "Beast",
		"the right hand side of a scanned unit line was dropped: " .. tostring(read[2][5]))

	------------------------------------------------------------------
	-- Nothing under the cursor, nothing on screen
	--
	-- The event fires with the token already cleared as well as with one
	-- resolved, and a part that opened on both would put a box up about
	-- whatever the last mob was.
	------------------------------------------------------------------

	guids.mouseover = nil
	fire("UPDATE_MOUSEOVER_UNIT")
	check(not Box.IsShown(), "a mouseover event with no unit behind it opened a box anyway")
	check(not ns.UI.Scan.Suppressing(),
		"Blizzard's tooltip is being held down with nothing of ours on screen")

	------------------------------------------------------------------
	-- The hover itself
	------------------------------------------------------------------

	-- On somebody else, which is the answer that needs no roster: the mob is on
	-- the wrong person and how far behind you are does not change that.
	state.threatReader = function(source)
		if source ~= "player" then
			return nil
		end
		return false, 2, 62
	end

	guids.mouseover = MOB
	cursor.x, cursor.y = 300, 500
	fire("UPDATE_MOUSEOVER_UNIT")

	check(Box.IsShown(), "a mouseover resolved and the addon put nothing up")
	check(Box.Owner() == Box.CURSOR,
		"the box was anchored to an owner, and a creature in the world is not a frame")

	local said = drawn()
	check(said[1] == "Snarlmouth",
		"the client's own first line is not the title: " .. tostring(said[1]))
	check(said[3] == "Silverpine Forest",
		"the client's third line is missing: " .. tostring(said[3]))

	------------------------------------------------------------------
	-- The hook, from the other end
	--
	-- Meter/Standing.lua registered one line against the unit kind at load and
	-- knows nothing about this part. Its line lands in the extra band, after
	-- everything the client said and before the hint.
	------------------------------------------------------------------

	check(said[4] == "Threat",
		"nothing the addon knows about a mob reached its tooltip: " .. table.concat(said, " / "))
	local _, standing = Box.Text(4)
	check(standing == "theirs, you are at 62%",
		"the threat line does not say where you stand: " .. tostring(standing))
	check(said[5] == "", "the hint is not spaced off the band above it")
	check(said[6]:find("world off", 1, true) ~= nil,
		"the hover does not name the switch that turns it off: " .. tostring(said[6]))
	check(#said == 6, ("the box drew %d lines rather than six"):format(#said))

	------------------------------------------------------------------
	-- Blizzard's own box, held down
	--
	-- Narrow twice: only while ours is up, and only for a tooltip that answers
	-- a unit. The second is the one worth the assertion. GameTooltip carries a
	-- quest reward, a link somebody clicked in chat and every other addon's
	-- lines, and a suppression that took those too would be a linked item that
	-- says nothing with no error anywhere to say why.
	------------------------------------------------------------------

	check(ns.UI.Scan.Suppressing(),
		"our box is up and the client's is not being held down, so the mob is described twice")
	check(H.blizzardTooltip("mouseover") == false,
		"the client raised its own tooltip on the mob and the addon left it standing")
	check(H.blizzardTooltip(nil) == true,
		"a tooltip that is not about a unit was taken down as well, which is every linked item in the game")

	------------------------------------------------------------------
	-- Where the box lands
	--
	-- Beside the pointer and clear of the arrow, which hangs down and to the
	-- right of the hotspot. The side is picked the way a frame's tooltip picks
	-- one, so a mob on the right of the screen throws its box left rather than
	-- into the clamp.
	--
	-- All of which is what the box does undocked, and undocked is not the
	-- default, so the switch is thrown for the length of this claim and handed
	-- back at the end of it. The docked corner is asserted in 48-tooltips.lua
	-- where the setting lives; what is proven here is the answer a creature
	-- gets when the player has asked for a box beside the cursor, which is the
	-- one anchor in the file that no frame can reach.
	------------------------------------------------------------------

	local wasDocked = Box.Docked()
	Box.SetDocked(false)

	-- The stub stands UIParent up with no size at all, so the middle of the
	-- screen is zero and every tooltip in every section above this one has been
	-- thrown to the same side without anybody noticing. This is the one section
	-- where which side the box picks is the subject, so it gives the screen a
	-- size for the length of that claim and hands it straight back. A size left
	-- behind would move the mirror line 15-skin-fit measures its blocks against.
	local screen = _G.UIParent
	screen:SetSize(2560, 1440)
	cursor.x, cursor.y = 300, 500
	fire("UPDATE_MOUSEOVER_UNIT")

	local px, py = pointer()
	check(edge("GetLeft") > px and edge("GetLeft") - px < 64,
		"the box did not open just to the right of the pointer on the left of the screen")
	check(edge("GetTop") < py and py - edge("GetTop") < 64,
		"the box did not open just under the arrow that opened it")

	local near = edge("GetLeft")
	cursor.x = cursor.x + 60
	fire("UPDATE_MOUSEOVER_UNIT")
	check(edge("GetLeft") > near, "the box did not follow the pointer")

	cursor.x = 2400
	fire("UPDATE_MOUSEOVER_UNIT")
	px = pointer()
	check(edge("GetRight") < px,
		"a mob on the right of the screen threw its box further right, into the clamp")

	screen:SetSize(0, 0)
	Box.SetDocked(wasDocked)
	cursor.x = 300
	fire("UPDATE_MOUSEOVER_UNIT")

	------------------------------------------------------------------
	-- Nothing to say about a friend
	--
	-- The threat source's own guard, not this part's. A line reading "not
	-- swinging at anybody" under every innkeeper in the game is what makes a
	-- player turn the whole hover off.
	------------------------------------------------------------------

	_G.WarriorKitFriendlyUnits.mouseover = true
	fire("UPDATE_MOUSEOVER_UNIT")
	said = drawn()
	check(said[4] ~= "Threat",
		"a quest giver was told where you stand on it: " .. table.concat(said, " / "))
	_G.WarriorKitFriendlyUnits.mouseover = nil

	------------------------------------------------------------------
	-- The other answers the threat line has
	--
	-- Two returns of nil percent for opposite reasons, which is the trap the
	-- line is written round: you are holding the mob and nobody is near you,
	-- and the mob has never heard of you.
	--
	-- The fourth answer is a client with no threat API at all, and it cannot be
	-- reached from here. Core/Core.lua resolves UnitDetailedThreatSituation into
	-- a file-scope local as it loads, so a test that took the global away
	-- afterwards would take nothing away, and there is no way to be a Classic
	-- Era client half way through a run. The threat pane's own Era fallback in
	-- Meter/Threat.lua is untested for exactly the same reason and in exactly
	-- the same place, which is worth saying out loud rather than leaving to be
	-- discovered: what Swinging words is proven by nothing here.
	------------------------------------------------------------------

	state.threatReader = function(source)
		if source ~= "player" then
			return nil
		end
		return true, 3, 100
	end
	fire("UPDATE_MOUSEOVER_UNIT")
	local _, holding = Box.Text(4)
	check(holding == "yours, and nobody is close",
		"holding a mob with nobody behind you reads as: " .. tostring(holding))

	state.threatReader = function() return nil end
	fire("UPDATE_MOUSEOVER_UNIT")
	local _, idle = Box.Text(4)
	check(idle == "nothing on it yet",
		"a mob that has never heard of you reads as: " .. tostring(idle))

	------------------------------------------------------------------
	-- Looking away
	--
	-- UPDATE_MOUSEOVER_UNIT says when a hover begins and nothing reliable about
	-- when one ends, so the box carries a ticker that runs only while it is on
	-- screen. Everything it took has to come back: the box, and Blizzard's own
	-- tooltip with it.
	------------------------------------------------------------------

	fire("UPDATE_MOUSEOVER_UNIT")
	check(Box.IsShown(), "the scene is not set up: nothing is on screen to look away from")

	guids.mouseover = nil
	World.Sweep(1)
	check(not Box.IsShown(), "the box stayed up after the pointer left the mob")
	check(not ns.UI.Scan.Suppressing(),
		"the client's tooltip is still held down with nothing of ours on screen")
	check(H.blizzardTooltip("mouseover") == true,
		"Blizzard's own tooltip is still being taken down after the addon let go")

	------------------------------------------------------------------
	-- Turned off
	--
	-- Including the box already on screen. A hover left standing when the
	-- setting goes off would sit there describing a mob under a hint line
	-- offering to do the thing you just did.
	------------------------------------------------------------------

	guids.mouseover = MOB
	fire("UPDATE_MOUSEOVER_UNIT")
	check(Box.IsShown(), "the scene is not set up: nothing is on screen to turn off")

	World.Set(false)
	check(not Box.IsShown(), "turning the world hover off left the box it had already opened")
	fire("UPDATE_MOUSEOVER_UNIT")
	check(not Box.IsShown(), "the world hover is off and a mouseover still opened a box")
	check(H.blizzardTooltip("mouseover") == true,
		"the world hover is off and the addon is still holding Blizzard's tooltip down")
	check(World.Describe():find("off", 1, true) ~= nil,
		"the part does not report that it is off: " .. World.Describe())

	World.Set(true)
	check(World.Describe() == "on, in the addon's own box",
		"the part does not report that it is working: " .. World.Describe())

	------------------------------------------------------------------
	-- A client that hands over nothing about a unit
	--
	-- The name still stands, the way it does on an item link the client refuses.
	-- A box carrying a threat reading over an unnamed thing is worse than a box
	-- carrying a name, and this is the branch that decides which one a player on
	-- a client with no SetUnit gets.
	------------------------------------------------------------------

	tooltips.unit.mouseover = nil
	state.threatReader = function(source)
		if source ~= "player" then
			return nil
		end
		return false, 2, 62
	end
	fire("UPDATE_MOUSEOVER_UNIT")
	check(Box.Text(1) == "Snarlmouth",
		"a client with no text about a unit did not fall back to the name: "
			.. tostring(Box.Text(1)))
	local _, still = Box.Text(2)
	check(still == "theirs, you are at 62%",
		"the addon's own line went with the client's: " .. tostring(still))

	tooltips.unit.mouseover = {
		{ "Snarlmouth" },
		{ "Level 62 Elite", "Beast" },
		{ "Silverpine Forest" },
	}

	------------------------------------------------------------------
	-- What the ticker costs
	--
	-- It runs only while the box is on screen, which is the fix, and it still
	-- has to cost nothing while it is: the question it asks is asked ten times a
	-- second for as long as you are pointing at anything, and the collector runs
	-- in the middle of a frame.
	------------------------------------------------------------------

	guids.mouseover = MOB
	fire("UPDATE_MOUSEOVER_UNIT")
	for _ = 1, 5 do
		World.Sweep(0.1)
	end
	collectgarbage("collect")
	collectgarbage("stop")
	local before = collectgarbage("count")
	for _ = 1, 50 do
		World.Sweep(0.1)
	end
	local churned = collectgarbage("count") - before
	collectgarbage("restart")
	check(churned < CHURN.world,
		("the world hover churned %.2f KB over 50 ticks, gate is %.2f")
			:format(churned, CHURN.world))
	check(Box.IsShown(), "fifty ticks over a mob that never moved took the box down")

	guids.mouseover = nil
	unitName.mouseover = nil
	tooltips.unit.mouseover = nil
	state.threatReader = nil
	cursor.x, cursor.y = 300, 500
	World.Close()
	H.blizzardTooltip(nil)

	print(("world  %s, %s; the client's own held down for a unit and nothing else; %.2f KB per 50 ticks, gate is %.2f")
		:format(World.Describe(),
			Box.Docked() and "docked in the corner" or "beside the pointer",
			churned, CHURN.world))
end
