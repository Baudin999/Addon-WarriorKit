local ADDON, ns = ...

local UI = ns.UI

--------------------------------------------------------------------------
-- Where the HUD goes while a screen window is up
--
-- A screen window is half the monitor of type with no ground under it, read
-- against whatever the player happens to be standing on. Every rectangle this
-- addon draws over the world is a rectangle that can land in the middle of it:
-- the missing buff row, the racial nag, the cooldowns, the swing bars, the
-- meters, the two feeds, the standing row and the three unit blocks. The sheet
-- is the one thing on screen you opened on purpose and it was the only thing
-- with anything drawn on top of it.
--
-- **Only what is actually under it.** This used to be one switch: a sheet up
-- meant every registered part away, wherever it sat. That is right for the
-- three rows the sheet lands on and wrong for the rest, and the rest is most of
-- them, because a sheet pinned to one edge of the monitor leaves the other edge
-- alone. You lost your swing timer to a sheet that was nowhere near it. So the
-- answer is per part and it is a rectangle test: a part hides when it overlaps
-- a window that has asked, and comes back the moment it does not. Partly
-- covered counts. A row with one corner under the sheet is a row you cannot
-- read, and the alternative is arguing about how much of a number has to be
-- missing before it stops being a number.
--
-- **Which means it is asked again, not answered once.** The picture moves for
-- more reasons than the sheet opening. Buffs/Nag.lua sets the missing buff row's
-- width from how many buffs are missing on every paint, Cooldowns/Row.lua sets
-- both of the cooldown row's from how many cooldowns are up, and the meters and
-- the rails do the same; the sheet itself is dragged, and it re-places itself
-- out of every rescale. Hooking each of those is six hooks and a seventh
-- somebody forgets next month. So the sweep below runs off a tick while a
-- window is up, and off nothing at all while none is.
--
-- **The frames stand down rather than being argued with.** Core/Attic.lua makes
-- the same move on the client's frames and its header carries the reasoning:
-- visibility in this client is a property of the parent chain, so a frame whose
-- parent is hidden is not drawn whatever anybody calls on the frame itself.
-- Every row here is driven by a ticker or an event that shows and hides it as
-- the fight goes, and a Hide called from this file would be undone on the next
-- tick. A hidden parent is not. One parent per part rather than one for all of
-- them, which is the whole of what the rectangle test needed underneath it.
--
-- **The row's own answer is untouched.** IsShown on a child of a hidden frame
-- still reads back what its owner last wrote, so the nag goes on deciding it
-- has three squares to draw, /wk status goes on saying so, and the row is
-- exactly as it was the moment the sheet comes off it. Nothing here has to be
-- told what any of these frames are for.
--
-- **The ticker keeps running.** OnUpdate stops on a frame that is not visible
-- and OnEvent does not, and every row in this addon puts its tick on a separate
-- event frame rather than on the rectangle, which Buffs/Nag.lua's own header
-- gives the reason for. That is load bearing twice over now: a row that stopped
-- resizing while it was covered would be measured at the size it had when it
-- went away, and would never come back at the size that clears the sheet.
--
-- **A cell is UIParent's size and shape.** These frames are anchored to
-- UIParent by the point UI/Placeable.lua wrote for them, so nothing about
-- where they sit depends on the cell at all. It matches anyway, because the one
-- that is not placed yet takes its default point from its parent and the answer
-- has to be the same either way. Scale is already independent: UI/Pixel.lua's
-- Adopt sets SetIgnoreParentScale on every frame that arrives, which is exactly
-- why the test below multiplies every corner back up by the frame's own scale
-- before comparing two of them.
--
-- **Nothing secure comes into a cell.** Reparenting is one of the calls the
-- client refuses an addon mid fight on a protected frame, and the sheet is
-- opened in a fight by a snippet. The action bars, the unit frames and the gear
-- squares are all protected. What a cell holds is a rectangle the addon draws
-- for itself, and it is only ever hidden and shown, which the client does not
-- care about on a frame with nothing protected inside it.
--
-- **The unit frames stand down by snippet instead.** Each one is an anchor of
-- ours with a secure unit button inside it, so it cannot be reparented and it
-- cannot be hidden from Lua in a fight, which is the fight the sheet is most
-- often opened in. They register through UI.HushableSecure below and a snippet
-- on the guard hides them, which is the sanctioned way an addon does a
-- protected thing in combat and the same way UI/Placeable.lua moves the sheet
-- itself. The anchor is what the snippet hides and never the button: the button
-- is driven by the client's own unit watch, and a hidden parent leaves that
-- answer alone the way it leaves a row's own flag alone.
--------------------------------------------------------------------------

-- How often the picture is read again while a window is up. A tenth of a
-- second is a row that trails the sheet's edge by at most that much on a drag,
-- and four corners off ten frames a second is a cost nothing on the performance
-- tab can separate from zero.
local INTERVAL = 0.1

local guard, pulse

-- Who has asked for quiet, keyed by the frame that asked.
--
-- A set rather than a count. A counter drifts the first time a show is paired
-- with two hides or a window comes up twice without going down, and what it
-- drifts into is a HUD that never comes back, which is a bug the player has no
-- way to read. A set can be written the same way twice and still be right.
--
-- It is also the list of rectangles a part is tested against: the key is the
-- window's own frame, so where the window is is read off it every sweep and a
-- sheet being dragged needs nothing said to this file.
local asked = {}

-- Every part that gets out from under a window, in the order it registered.
--
-- One list and not two, because the question asked of each is the same question
-- and only the delivery differs: a plain part is parented into a cell this file
-- hides, a part holding something protected keeps its parent and a snippet
-- hides it. `over` is the answer last written and it is what makes a sweep that
-- finds nothing moved cost four reads and no writes.
local parts = {}

-- How many of those went to the guard, which is the number the snippet counts
-- through, and how many times it has been told to act. The turn exists because
-- the client drops a SetAttribute that writes the value the attribute already
-- holds: a snippet hung off a flag would sit still on the one write that has to
-- land, which is a block registering while the sheet is already up.
local secured, turns = 0, 0

-- Hide them, or give them back, from inside the restricted environment.
--
-- A flag per frame rather than one for all of them, because the sheet covers
-- the player block and the target block at different moments and covers target
-- of target on neither. Read off the guard rather than passed in: the value
-- that arrives with the turn is the turn. Frame refs are the only handles a
-- snippet has, so the registration below writes one per frame under a name this
-- can count through.
local QUIET = [[
	if name ~= "wk-turn" then return end
	local count = self:GetAttribute("wk-count") or 0
	for index = 1, count do
		local frame = self:GetFrameRef("wk-" .. index)
		if frame then
			if self:GetAttribute("wk-down-" .. index) then
				frame:Hide()
			else
				frame:Show()
			end
		end
	end
]]

local function Guard()
	if not guard then
		guard = CreateFrame("Frame", "WarriorKitHushGuard", UIParent,
			"SecureHandlerAttributeTemplate")
		guard:SetAttribute("_onattributechanged", QUIET)
	end
	return guard
end

-- Where a frame is on the monitor, in the monitor's own units.
--
-- Multiplied by the frame's own effective scale because that is what the four
-- getters divide by, and two frames on this list do not share one: UI/Pixel.lua
-- takes every frame it adopts off its parent's scale and writes its own, so a
-- row drawn at 0.8 and a sheet drawn at 1.3 answer the same corner with two
-- different numbers. Nil where the client has no answer, which is a frame that
-- has never been laid out, and the caller reads that as nothing to compare.
local function Rect(frame)
	local left, bottom = frame:GetLeft(), frame:GetBottom()
	local right, top = frame:GetRight(), frame:GetTop()
	if not left or not bottom or not right or not top then
		return nil
	end
	local scale = frame:GetEffectiveScale() or 1
	return left * scale, bottom * scale, right * scale, top * scale
end

-- Whether a frame is under any window that has asked for quiet.
--
-- Strict on all four sides, so a row parked exactly against the sheet's edge
-- keeps drawing and one that laps over it by a pixel does not. Two rectangles
-- that share an edge overlap in no pixel, and a row that went away for touching
-- the sheet would be a row you cannot park beside it.
local function Under(frame)
	local left, bottom, right, top = Rect(frame)
	if not left then
		return false
	end
	for who in pairs(asked) do
		local theirLeft, theirBottom, theirRight, theirTop = Rect(who)
		if theirLeft and left < theirRight and right > theirLeft
			and bottom < theirTop and top > theirBottom then
			return true
		end
	end
	return false
end

-- The whole of the decision, run on every change and ten times a second while a
-- window is up.
--
-- Edge triggered on purpose. Reading four corners off a frame is cheap and
-- writing to one is not, and the write on the secure half is a snippet the
-- client runs: a sweep that touched every part every tick would run that
-- snippet ten times a second in the fight the sheet is most often open in. What
-- is stored is the last answer, and a part whose answer has not moved is read
-- and left alone.
--
-- The guard is read off the upvalue rather than through Guard(), because a part
-- carrying a flag is a part that registered through the guard and there is
-- nothing to build here. Nothing on this path builds anything.
local function Sweep()
	local turned = false
	for index = 1, #parts do
		local part = parts[index]
		local over = Under(part.frame)
		if over ~= part.over then
			part.over = over
			if part.cell then
				if over then
					part.cell:Hide()
				else
					part.cell:Show()
				end
			else
				guard:SetAttribute(part.flag, over)
				turned = true
			end
		end
	end
	if turned then
		turns = turns + 1
		guard:SetAttribute("wk-turn", turns)
	end
end

-- The tick, and the frame that gates it.
--
-- Hidden and shown rather than started and stopped, which is what UI/Ticker.lua
-- says a frame argument is for and what UI/Tooltip.lua and World/World.lua
-- already do with theirs. Nothing is registered here that can hide this frame
-- by accident: it is parentless and this file owns both calls.
--
-- Named, because a section of the harness has to reach the tick to beat it and
-- UI.Ticking takes the frame the tick hangs off.
local function Arm()
	if pulse then
		return
	end
	pulse = CreateFrame("Frame", "WarriorKitHushPulse")
	pulse:Hide()
	UI.Ticker(pulse, INTERVAL, "hush", Sweep)
end

-- A frame that gets out from under a screen window.
--
-- Called once, at the moment the frame is built and before it is placed. There
-- is no matching call to take one back out: a part that draws over the world
-- draws over the world for the whole session, and the switch that turns the
-- part off hides its own frame.
--
-- A cell of its own rather than one room for all of them. The room was right
-- while the answer was one switch and cannot hold a per part answer at all,
-- and what it cost to split is one frame per registrant, which is eight.
function UI.Hushable(frame)
	local cell = CreateFrame("Frame", nil, UIParent)
	cell:SetAllPoints(UIParent)
	frame:SetParent(cell)
	parts[#parts + 1] = { frame = frame, cell = cell, over = false }
	Arm()
end

-- The same, for a frame that holds something protected.
--
-- Called once and out of combat, the same as a cell's own registration, and for
-- a harder reason: handing a snippet a frame reference is an attribute write on
-- a secure handler and the count it reads is another. Swept on the way out so a
-- block built while a sheet is already over it goes away now rather than on the
-- next tick.
function UI.HushableSecure(frame)
	secured = secured + 1
	local watcher = Guard()
	watcher:SetFrameRef("wk-" .. secured, frame)
	watcher:SetAttribute("wk-count", secured)
	parts[#parts + 1] = { frame = frame, flag = "wk-down-" .. secured, over = false }
	Arm()
	Sweep()
end

-- Ask for quiet, or give it back, on behalf of one window.
--
-- Swept here as well as on the tick, so a sheet opening takes the rows under it
-- away on the same frame rather than a tenth of a second later, and so the last
-- window going down gives every part back before the tick that would have is
-- switched off.
--
-- Show and Hide rather than SetShown, which is the rule Core/Attic.lua's header
-- states from the other end: SetShown is resolved in C and walks past a Lua
-- Show. Nothing replaces this frame's, and a cell is still shut and opened by
-- the pair the rest of the addon uses.
function UI.Hush(who, on)
	asked[who] = on or nil
	Arm()
	local quiet = next(asked) ~= nil
	if quiet then
		pulse:Show()
	else
		pulse:Hide()
	end
	Sweep()
	return quiet
end

-- Whether any window has asked. For /wk status, which reports the setting
-- rather than the picture: what is actually standing down is now a different
-- answer per part and UI.Hushing below is where a caller asks that.
function UI.Hushed()
	return next(asked) ~= nil
end

-- How a frame stands down, and whether anything registered it at all.
--
-- "cell" for a frame parented into one of ours, "guard" for one the snippet
-- hides, nil for a frame nobody registered. For the harness, which cannot read
-- either off the frame: a cell has no name and the guard's answer is an
-- attribute. Walked rather than keyed by the frame, because the list is eight
-- long and nothing asks this on a tick.
function UI.Hushing(frame)
	for index = 1, #parts do
		if parts[index].frame == frame then
			return parts[index].cell and "cell" or "guard"
		end
	end
	return nil
end
