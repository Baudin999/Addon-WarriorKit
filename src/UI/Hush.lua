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
-- **Nothing secure comes into the room.** Reparenting is one of the calls the
-- client refuses an addon mid fight on a protected frame, and the sheet is
-- opened in a fight by a snippet. The action bars, the unit frames and the gear
-- squares are all protected. What the room holds is the rectangles the addon
-- draws for itself, and it is only ever hidden and shown, which the client does
-- not care about on a frame with nothing protected inside it.
--
-- **The unit frames stand down by snippet instead.** The player block and the
-- target block are the two rectangles most likely to be under a sheet pinned to
-- an edge of the monitor, and they are the two this file could not touch: each
-- one is an anchor of ours with a secure unit button inside it, so it cannot be
-- reparented and it cannot be hidden from Lua in a fight, which is the fight
-- the sheet is most often opened in. They register through UI.HushableSecure
-- below and a snippet on the guard hides them, which is the sanctioned way an
-- addon does a protected thing in combat and the same way UI/Placeable.lua
-- moves the sheet itself. The anchor is what the snippet hides and never the
-- button: the button is driven by the client's own unit watch, and a hidden
-- parent leaves that answer alone the way it leaves a row's own flag alone.
--------------------------------------------------------------------------

local holder, guard

-- Who has asked for quiet, keyed by the frame that asked.
--
-- A set rather than a count. A counter drifts the first time a show is paired
-- with two hides or a window comes up twice without going down, and what it
-- drifts into is a HUD that never comes back, which is a bug the player has no
-- way to read. A set can be written the same way twice and still be right.
local asked = {}

-- The frames the guard hides, in the order they registered, and how many times
-- it has been told to. The count is what the snippet acts on and it is why the
-- turn exists at all: the client drops a SetAttribute that writes the value the
-- attribute already holds, so a snippet hung off the flag itself would sit
-- still on the one write that has to land, which is a block registering while
-- the sheet is already up.
local hushed = {}
local turns = 0

-- Hide them, or give them back, from inside the restricted environment.
--
-- Read off the guard rather than passed in, because the value that arrives with
-- the turn is the turn. Frame refs are the only handles a snippet has, so the
-- registration below writes one per frame under a name this can count through.
local QUIET = [[
	if name ~= "wk-turn" then return end
	local down = self:GetAttribute("wk-down")
	local count = self:GetAttribute("wk-count") or 0
	for index = 1, count do
		local frame = self:GetFrameRef("wk-" .. index)
		if frame then
			if down then
				frame:Hide()
			else
				frame:Show()
			end
		end
	end
]]

local function Room()
	if not holder then
		holder = CreateFrame("Frame", "WarriorKitHush", UIParent)
		holder:SetAllPoints(UIParent)
	end
	return holder
end

local function Guard()
	if not guard then
		guard = CreateFrame("Frame", "WarriorKitHushGuard", UIParent,
			"SecureHandlerAttributeTemplate")
		guard:SetAttribute("_onattributechanged", QUIET)
	end
	return guard
end

-- Push the answer at the snippet. The flag first and the turn last, for the
-- reason UI/Placeable.lua writes its offsets before its count: the turn is what
-- runs the snippet and the snippet reads the flag.
local function Drive(quiet)
	if #hushed == 0 then
		return
	end
	local watcher = Guard()
	turns = turns + 1
	watcher:SetAttribute("wk-down", quiet)
	watcher:SetAttribute("wk-turn", turns)
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

-- The same, for a frame that holds something protected.
--
-- Called once and out of combat, the same as the room's own registration, and
-- for a harder reason: handing a snippet a frame reference is an attribute
-- write on a secure handler and the count it reads is another. Driven on the
-- way out so a block built while a sheet is already up goes away with it rather
-- than waiting for the next open.
function UI.HushableSecure(frame)
	hushed[#hushed + 1] = frame
	local watcher = Guard()
	watcher:SetFrameRef("wk-" .. #hushed, frame)
	watcher:SetAttribute("wk-count", #hushed)
	Drive(UI.Hushed())
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
	Drive(quiet)
	return quiet
end

-- Whether the HUD is standing down. For the harness and for /wk status.
function UI.Hushed()
	return next(asked) ~= nil
end
