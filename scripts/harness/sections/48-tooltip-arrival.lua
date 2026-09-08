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
-- The sharp claim in the first half is that a box refused for want of the
-- client's text is exactly the box the event has to be able to put up. The
-- rebuild used to be gated on a box being on screen: the hovers that most
-- needed it were the only ones that could not have it.
--
-- The second half is the other fetch, and it is a different shape of the same
-- defect. A spell's own text is fetched separately from the item that prints
-- it, so a book teaching a profession draws a box with every line on it but the
-- one it is carried for. That box looks finished, which is why the thinness
-- test could not see it and why the addon has to ask the client for the
-- sentence rather than wait for one nobody requested.

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

	------------------------------------------------------------------
	-- The line the item is for, which is fetched after the item
	--
	-- A book that teaches a profession is a tooltip with a name, a level and a
	-- requirement on it and nothing at all about what it does, because the Use
	-- line is the spell's own sentence and the client fetches a spell's text
	-- separately. Everything above is about a box with nothing in it; this is a
	-- box that looks finished and is not, which is why the thinness test could
	-- not see it and why the fix is a second question rather than a second
	-- reading of the same one.
	------------------------------------------------------------------

	local book = _G.WarriorKitItemLink("Master First Aid - Doctor in the House")
	local USE = "Use: Teaches you advanced first aid, allowing a maximum of 375 first aid skill."

	-- Asked as whether the sentence is anywhere in the box rather than as a line
	-- count, because the count is not this section's to predict: an item hover
	-- carries whatever the sources registered for items had to say about it, and
	-- a claim written as "three lines" is a claim that breaks when the seventh
	-- source lands.
	local function Says(text)
		for index = 1, Box.Lines() do
			if Box.Text(index) == text then
				return true
			end
		end
		return false
	end

	H.tooltips.item[book] = {
		{ "Master First Aid - Doctor in the House" },
		{ "Requires First Aid (300)" },
	}
	Tip.Open(owner, { kind = "item", link = book })
	check(Says("Requires First Aid (300)"), "the book drew none of the client's own text")
	check(Says(USE) == false, "the book's Use line was drawn before its spell arrived")

	-- Asked for, and that is the half that has to be asserted separately: a box
	-- that draws nothing about the book and never asks the client for the
	-- sentence is a box that will draw nothing about it forever.
	check(H.spellData.asked[#H.spellData.asked] == 27029,
		"nothing asked the client for the spell the book's Use line describes")

	H.spellData.cached[27029] = true
	H.tooltips.item[book][3] = { USE }
	fire("SPELL_DATA_LOAD_RESULT", 27029, true)
	check(Says(USE), "what the book does is still missing after its spell landed")

	-- And it stops. Every spell anybody loads fires this, and a box whose own
	-- text is complete has nothing left to wait for.
	check(Tip.Arrived() == false,
		"a book that already says what it does rebuilt for a spell landing anyway")

	Tip.Close(true)
	H.tooltips.item[book] = nil
	H.spellData.cached[27029] = nil

	print("tips   a link with nothing behind it draws nothing, and fills in where it stands when the item lands; a book asks for the spell its Use line describes and says what it does when that lands too")
end
