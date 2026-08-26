local ADDON, ns = ...

local Square = {}
ns.Square = Square

--------------------------------------------------------------------------
-- What one square answers to the mouse
--
-- Buttons/Bars.lua builds the squares, points each one at an action slot and
-- draws what that slot is doing. None of that involves the cursor. This file is
-- the other half: what happens when you put the mouse on a square and what
-- happens when you drag something onto it.
--
-- Split out when Bars.lua crossed the 800 line gate, and the seam is a real one
-- rather than the first convenient cut. Everything here hangs a script on a
-- button and touches the cursor; nothing here knows what a bar is, how many
-- there are, or which slot a square points at, because it reads that off the
-- button's own action attribute the same way the tick does.
--
-- Both were on Bars.lua's list of what a square deliberately was not, and
-- neither should have been.
--
-- The tooltip, which is how you find out what rank of Rend the loadout put in
-- slot four without dragging anything anywhere. It is also the loudest thing
-- missing from a square standing in for a button that has one: hovering a bar
-- and getting nothing back reads as broken, not as minimal.
--
-- And the drag, which was refused because PickupAction and PlaceAction on a
-- frame you can drop anything onto is a way to lose a bar to a misclick. The
-- risk is real and the conclusion did not follow, because the alternative on
-- offer was worse: with Blizzard's buttons hidden underneath, nothing could be
-- dropped on a bar at all, so learning a spell meant turning the whole clone
-- off to place it and back on afterwards. A misclick moves one slot and drops
-- what it picked up back where it came from. Nothing is destroyed and the
-- picture is right on the next tick.
--
-- OnEnter, OnLeave, OnDragStart and OnReceiveDrag are none of them protected,
-- which is why a secure action button will take all four in plain Lua. Nothing
-- here runs on a ticker.
--------------------------------------------------------------------------

-- What is on this square, said in the client's own words.
--
-- OnEnter and OnLeave are not protected, so this is one of the few things a
-- secure button will let an addon put on it in plain Lua. The slot is read off
-- the button's own action attribute for the reason Bars.Update reads it there:
-- it is what a press would actually reach, whether Lua wrote it or the stance
-- snippet did.
--
-- Refused for an empty slot rather than left to SetAction. SetAction on a slot
-- with nothing in it fills nothing and leaves whatever the last tooltip said on
-- screen, anchored to a square that has no ability, which is worse than no
-- tooltip at all.
local function Tooltip(w)
	w:SetScript("OnEnter", function(self)
		local slot = self:GetAttribute("action")
		if not slot or not ns.Slot.Texture(slot) then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetAction(slot)
		GameTooltip:Show()
	end)
	w:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
end

-- Picking a slot up and putting one down.
--
-- The two halves of one gesture and the only way to fill a square by hand,
-- because the Blizzard button this one stands over is hidden and cannot be
-- dropped on.
--
-- Both go through ns.Layout.CanCarry rather than testing the API here. That
-- file already probes PickupAction and PlaceAction, already knows this client
-- may not have them, and already refuses in combat. A second probe would be a
-- second answer to a question that has one.
--
-- Deliberately not Layout.CanWrite, which also refuses while the cursor is
-- holding something. That is the right question for a loadout filling twelve
-- slots from empty hands and the wrong one here: a drop happens with a spell on
-- the cursor by definition, and asking CanWrite would refuse every drop with
-- "put down what you are holding first".
local function Carry(w)
	w:RegisterForDrag("LeftButton")

	w:SetScript("OnDragStart", function(self)
		if not ns.Layout.CanCarry() then
			return
		end
		local slot = self:GetAttribute("action")
		if slot then
			PickupAction(slot)
		end
	end)

	w:SetScript("OnReceiveDrag", function(self)
		if not ns.Layout.CanCarry() then
			return
		end
		local slot = self:GetAttribute("action")
		if slot then
			PlaceAction(slot)
		end
	end)
end

-- Both, on one square. One call rather than two exported, because a square that
-- got the tooltip and not the drag is a square you can read and cannot fill,
-- and there is no reason to want that.
function Square.Handle(w)
	Tooltip(w)
	Carry(w)
end
