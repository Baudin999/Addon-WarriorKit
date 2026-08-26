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

-- A refusal nobody can see is indistinguishable from a bar that ignores the
-- mouse, which is what this cost an evening to find out.
--
-- Both halves used to answer a false CanCarry with a bare return. The spell
-- stayed on the cursor, the square stayed empty, and nothing on screen said
-- why. Two of the three reasons that call can refuse are permanent for the
-- session, because this client has no PickupAction or no PlaceAction at all,
-- and that is worth one line in chat rather than an evening of dragging.
--
-- Once per reason rather than once per square: a drag along a bar passes over
-- twelve of them and twelve identical lines is not a better answer than one.
-- Keyed by the line itself, so a second thing going wrong still gets said;
-- the first version latched on the first message and swallowed every other
-- reason for the rest of the session, which is the same silence one layer up.
--
-- Combat is never reported, because it clears on its own and because a fight
-- is when the chat frame has the least room for a sentence you did not need.
local told = {}

local function Say(line)
	if not line or told[line] then
		return
	end
	told[line] = true
	ns.Print(line)
end

local function Refused(why)
	if not why or why == ns.Layout.BUSY_COMBAT then
		return
	end
	Say("nothing can be dropped on a square: " .. why .. ".")
end

-- What the cursor is holding, as the three values a drop is judged by.
--
-- PlaceAction on a slot that already has something swaps: the slot takes what
-- was on the cursor and the cursor takes what was in the slot. So "the cursor
-- is still loaded" is not a failure and "the cursor is loaded with exactly what
-- it was loaded with" is, which is why all three fields are compared rather
-- than the presence of a cursor at all.
local function Cursor()
	if type(GetCursorInfo) ~= "function" then
		return nil
	end
	return GetCursorInfo()
end

local function Carry(w)
	w:RegisterForDrag("LeftButton")

	w:SetScript("OnDragStart", function(self)
		local slot = self:GetAttribute("action")
		ns.BarTrace.Say(("pick up from slot %s, cursor %s"):format(
			tostring(slot), ns.BarTrace.Cursor()))
		local can, why = ns.Layout.CanCarry()
		if not can then
			return Refused(why)
		end
		if slot then
			PickupAction(slot)
		end
		ns.BarTrace.Say("after the pick up, cursor " .. ns.BarTrace.Cursor())
	end)

	w:SetScript("OnReceiveDrag", function(self)
		local slot = self:GetAttribute("action")
		ns.BarTrace.Say(("drop on slot %s, cursor %s"):format(
			tostring(slot), ns.BarTrace.Cursor()))

		local can, why = ns.Layout.CanCarry()
		if not can then
			return Refused(why)
		end

		-- A square with no slot behind it is the one refusal that is this
		-- addon's own fault rather than the client's, and it is the state a
		-- bar 1 whose pages never arrived would sit in: it draws, it hovers and
		-- it presses, because every one of those reads the same missing
		-- attribute and finds nothing to complain about.
		if not slot then
			return Say("that square is not pointing at an action slot, so nothing can be put on it.")
		end

		local kind, first, second = Cursor()
		local was = ns.Slot.Texture(slot)
		PlaceAction(slot)
		local after, one, two = Cursor()
		ns.BarTrace.Say("after the drop, cursor " .. ns.BarTrace.Cursor())

		-- The drop reached us, the client took the call, and nothing moved:
		-- the cursor is holding what it went in with and the slot is holding
		-- what it already had. That is the one outcome that used to look
		-- exactly like a bar the mouse never reached.
		--
		-- The slot is checked as well as the cursor because a swap leaves the
		-- cursor full by design, and because dropping a spell onto a slot that
		-- already holds it leaves the cursor looking untouched. Said as what is
		-- known rather than as a diagnosis: nothing moved, and whether that is
		-- the client refusing the slot or a drop that had nothing to do is not
		-- something this line can tell.
		if kind and after == kind and one == first and two == second
			and ns.Slot.Texture(slot) == was then
			Say(("dropping that on action slot %d changed nothing."):format(slot))
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
