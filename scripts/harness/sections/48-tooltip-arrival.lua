-- The item the client has not fetched yet
--
-- An item is a number until the server has sent its data, and a hover that
-- lands inside that window reads a tooltip the client cannot fill in. There are
-- two ways that showed and they are the same defect: a box with a name and
-- nothing under it where the caller had a title of its own, and no box at all
-- where it did not, because a subject with nothing in any band is refused
-- rather than drawn empty.
--
-- Neither ever corrected itself. The head band is scanned once, at the moment
-- the pointer arrives, and nothing in the addon was listening on behalf of a
-- box already on screen. GET_ITEM_INFO_RECEIVED is the client saying it now
-- knows, and this section is what UI/Tip.lua does with it.
--
-- Its own file for the reason 48-tooltip-fresh.lua is one. Both are about a box
-- that has to change after it was drawn, both are driven rather than hovered,
-- and neither is a claim about what a tooltip says: 48-tooltips.lua is the
-- bands, the sources and the placements, and it is at the line ceiling every
-- section shares.
--
-- Four claims, and the last is the sharp one. A box that was refused for want
-- of the client's text is exactly the box the event has to be able to put up,
-- and the rebuild used to be gated on a box being on screen: the hovers that
-- most needed it were the only ones that could not have it.

local H = ...
local ns, check, fire = H.ns, H.check, H.fire

do
	local Tip, Box = ns.Tip, ns.UI.Tooltip
	local owner = CreateFrame("Frame", nil, _G.UIParent)
	owner:SetSize(30, 30)
	owner:SetPoint("CENTER", _G.UIParent, "CENTER", 0, 0)

	------------------------------------------------------------------
	-- A link with nothing behind it
	--
	-- The name is deliberately absent from the stub's own item table, which is
	-- that file's model of "not cached yet": every lookup a source reads answers
	-- nil for it and the scanner answers nil too. That is the whole of the
	-- state, and it is the state a link out of the chat log lands in.
	------------------------------------------------------------------

	local late = _G.WarriorKitItemLink("Late Arrival")

	Tip.Open(owner, { kind = "item", link = late })
	check(Box.IsShown() == false,
		"an item the client says nothing about drew a box with nothing in it")

	-- The data lands while the pointer has not moved.
	H.tooltips.item[late] = { { "Late Arrival" }, { "Head, Plate" } }
	fire("GET_ITEM_INFO_RECEIVED", 4201)
	check(Box.IsShown(), "the box never came up after the item arrived")
	check(Box.Text(1) == "Late Arrival",
		"the box that came up says " .. tostring(Box.Text(1)))

	------------------------------------------------------------------
	-- And what does not rebuild
	--
	-- Every item anybody loots fires this event. A box that rebuilt on all of
	-- them would be a raid's whole item traffic landing on one hover, so the
	-- test is the state of the box rather than the id that arrived: thin is
	-- worth rebuilding and anything else is not.
	------------------------------------------------------------------

	check(Tip.Arrived() == false,
		"a box with the client's own text in it rebuilt for an item arriving anyway")

	Tip.Open(owner, { kind = "note", title = "A note" })
	check(Tip.Arrived() == false, "a note rebuilt itself for an item arriving")

	-- The pointer having left is the end of it. The hover record is what says
	-- so, and a box counted down by the linger is not a hover.
	Tip.Close(true)
	check(Tip.Arrived() == false, "an item arriving rebuilt a hover nobody is on")

	------------------------------------------------------------------
	-- The same thing one slot at a time
	--
	-- A worn piece is read from the slot rather than from a link, so it lands on
	-- a different setter and a different half of the client's cache. That is the
	-- character sheet, where nineteen hovers all read a slot and this was first
	-- noticed; 52-character.lua asserts it on the page itself, and here it is on
	-- the subject alone.
	------------------------------------------------------------------

	H.tooltips.inventory[H.tooltipKey("player", 5)] = nil
	Tip.Open(owner, { kind = "inventory", unit = "player", slot = 5,
		title = "Breastplate of the Second" })
	check(Box.Text(1) == "Breastplate of the Second",
		"a worn slot with no text yet drew " .. tostring(Box.Text(1)))
	check(Box.Lines() == 1,
		("a worn slot the client cannot describe drew %d lines"):format(Box.Lines()))

	H.tooltips.inventory[H.tooltipKey("player", 5)] = {
		{ "Breastplate of the Second" }, { "Chest, Plate" }, { "120 Armor" },
	}
	fire("GET_ITEM_INFO_RECEIVED", 4202)
	check(Box.Lines() == 3,
		("the worn slot did not fill in when its item arrived, %d lines"):format(Box.Lines()))
	check(Box.Text(3) == "120 Armor",
		"the client's own last line is missing: " .. tostring(Box.Text(3)))

	Tip.Close(true)
	H.tooltips.item[late] = nil
	H.tooltips.inventory[H.tooltipKey("player", 5)] = nil

	print("tips   a link with nothing behind it draws nothing, and fills in where it stands when the item lands")
end
