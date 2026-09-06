local ADDON, ns = ...

local UI = ns.UI

--------------------------------------------------------------------------
-- Where the HUD goes while a screen window is up
--
-- A screen window is half the monitor of type with no ground under it, read
-- against whatever the player happens to be standing on. Every rectangle this
-- addon draws over the world is a rectangle that can land in the middle of it:
-- the missing buff row, the racial nag, the cooldowns, the swing bars, the
-- meters, the two feeds and the standing row. The sheet is the one thing on
-- screen you opened on purpose and it was the only thing with anything drawn
-- on top of it.
--
-- The frames stand down instead of being argued with, and that is the whole
-- design. Core/Attic.lua makes the same move on the client's frames and its
-- header carries the reasoning: visibility in this client is a property of the
-- parent chain, so a frame whose parent is hidden is not drawn whatever anybody
-- calls on the frame itself. Every one of the seven rows is driven by a ticker
-- or an event that shows and hides it as the fight goes, and a Hide called from
-- here would be undone on the next tick. A hidden parent is not.
--
-- **The row's own answer is untouched.** IsShown on a child of a hidden frame
-- still reads back what its owner last wrote, so the nag goes on deciding it
-- has three squares to draw, /wk status goes on saying so, and the row is
-- exactly as it was the moment the sheet comes down. Nothing here has to be
-- told what any of these frames are for.
--
-- **The ticker keeps running.** OnUpdate stops on a frame that is not visible
-- and OnEvent does not, and every row in this addon puts its tick on a separate
-- event frame rather than on the rectangle, which Buffs/Nag.lua's own header
-- gives the reason for. So none of them go stale in here.
--
-- **The room is UIParent's size and shape.** These frames are anchored to
-- UIParent by the point UI/Placeable.lua wrote for them, so nothing about
-- where they sit depends on this frame at all. It matches anyway, because the
-- one that is not placed yet takes its default point from its parent and the
-- answer has to be the same either way. Scale is already independent:
-- UI/Pixel.lua's Adopt sets SetIgnoreParentScale on every frame that arrives.
--
-- **Nothing secure comes here.** Reparenting is one of the calls the client
-- refuses an addon mid fight on a protected frame, and the sheet is opened in a
-- fight by a snippet. The action bars, the unit frames and the gear squares are
-- all protected and none of them is registered. What is registered is the seven
-- rectangles the addon draws for itself, and the room is only ever hidden and
-- shown, which the client does not care about on a frame with nothing
-- protected inside it.
--------------------------------------------------------------------------

local holder

-- Who has asked for quiet, keyed by the frame that asked.
--
-- A set rather than a count. A counter drifts the first time a show is paired
-- with two hides or a window comes up twice without going down, and what it
-- drifts into is a HUD that never comes back, which is a bug the player has no
-- way to read. A set can be written the same way twice and still be right.
local asked = {}

local function Room()
	if not holder then
		holder = CreateFrame("Frame", "WarriorKitHush", UIParent)
		holder:SetAllPoints(UIParent)
	end
	return holder
end

-- A frame that stands down while a screen window is up.
--
-- Called once, at the moment the frame is built and before it is placed. There
-- is no matching call to take one back out: a part that draws over the world
-- draws over the world for the whole session, and the switch that turns the
-- part off hides its own frame.
function UI.Hushable(frame)
	frame:SetParent(Room())
end

-- Ask for quiet, or give it back, on behalf of one window.
--
-- Show and Hide rather than SetShown, which is the rule Core/Attic.lua's header
-- states from the other end: SetShown is resolved in C and walks past a Lua
-- Show. Nothing replaces this frame's, and the room is still shut and opened by
-- the pair the rest of the addon uses.
function UI.Hush(who, on)
	asked[who] = on or nil
	local quiet = next(asked) ~= nil
	local room = Room()
	if quiet then
		room:Hide()
	else
		room:Show()
	end
	return quiet
end

-- Whether the HUD is standing down. For the harness and for /wk status.
function UI.Hushed()
	return next(asked) ~= nil
end
