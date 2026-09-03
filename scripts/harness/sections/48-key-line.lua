--------------------------------------------------------------------------
-- Which key presses it
--
-- The hearthstone's tooltip said everything the client knows about a
-- hearthstone and nothing about which key you press for it, because the key is
-- a fact about the action slot it is standing on and the item's box never
-- asked. Buttons/Bound.lua joins the two: an item subject is walked through
-- the slots for the one holding its id, an action subject is a slot already,
-- and both get the same line.
--
-- Two readings and both are asserted, because they come from different places.
-- With the clone up, GetBindingKey no longer answers for a key the clone holds
-- an override on, so the line has to come off what Bars.ApplyBindings recorded.
-- With the clone down it has to come off the binding set. A test that only ran
-- one of them is a tooltip that goes blank when the bars are switched.
--------------------------------------------------------------------------

local H = ...
local ns, check = H.ns, H.check

do
	local Tip, Bound, Bars = ns.Tip, ns.Bound, ns.Bars
	local slots = _G.WarriorKitSlots
	local ART = "Interface\\Icons\\INV_Misc_Rune_01"
	local link = "|cffffffff|Hitem:6948::::::::60:::::|h[Hearthstone]|h|r"

	local function key(subject)
		local data = Tip.Build(subject)
		for index = 1, data and #data or 0 do
			if data[index][1] == "Key" then
				return data[index][2]
			end
		end
		return nil
	end

	check(Bound.Text("SHIFT-BUTTON3") == "Shift-Mouse 3",
		("SHIFT-BUTTON3 reads as %q"):format(Bound.Text("SHIFT-BUTTON3")))
	check(Bound.Text("CTRL-NUMPAD7") == "Ctrl-Num 7",
		("CTRL-NUMPAD7 reads as %q"):format(Bound.Text("CTRL-NUMPAD7")))
	check(Bound.Text("Z") == "Z", "a letter is not left alone")

	-- Not on any bar: the item's box says nothing about a key, because most of
	-- the bag is not on a bar and a "none" on every stack of cloth is noise.
	check(key({ kind = "item", link = link }) == nil,
		"a hearthstone on no bar got a key line")

	-- On bar 1, in the stance the player is in. Slot three of the page bar 1
	-- reads right now is ACTIONBUTTON3, which the stub binds to Z.
	local base = ns.Layout.SlotOf("ActionButton1")
	check(type(base) == "number", "the stub's ActionButton1 has no slot")
	local seat = base + 2
	slots[seat] = { item = 6948, texture = ART }
	check(Bound.Command(seat) == "ACTIONBUTTON3",
		("slot %d answers to %s"):format(seat, tostring(Bound.Command(seat))))
	check(key({ kind = "item", link = link }) == "Z",
		("the hearthstone on slot %d says its key is %s")
			:format(seat, tostring(key({ kind = "item", link = link }))))
	check(key({ kind = "action", slot = seat }) == "Z",
		"the square's own tooltip does not say the key the item's does")

	-- Off the current page. The same key presses it once the stance changes,
	-- and the tooltip says so rather than going blank.
	local pages = ns.Layout.Bar1Bases()
	check(type(pages) == "table" and #pages >= 2, "a warrior's bar 1 does not page")
	local away = pages and pages[2] and pages[2] + 2
	if away and away ~= seat then
		slots[seat] = nil
		slots[away] = { item = 6948, texture = ART }
		check(key({ kind = "item", link = link }) == "Z",
			("the hearthstone on another stance's page, slot %d, says %s")
				:format(away, tostring(key({ kind = "item", link = link }))))
		slots[away] = nil
		slots[seat] = { item = 6948, texture = ART }
	end

	-- Both readings. Whichever state the sections above left the clone in, the
	-- other is forced here and put back.
	local on = Bars.Keys() > 0
	check(on == (Bars.Held("ACTIONBUTTON3") ~= nil),
		"the clone holds keys and did not record them, or the other way round")
	if on then
		check(_G.GetBindingKey("ACTIONBUTTON3") == nil,
			"the stub hands a key back that the clone holds an override on")
	end
	local was = ns.db.actionBars
	ns.db.actionBars = not was
	check(Bars.Apply(), "flipping the clone reported combat deferring it")
	check(key({ kind = "item", link = link }) == "Z",
		("with the clone %s the hearthstone's key reads %s")
			:format(was and "off" or "on", tostring(key({ kind = "item", link = link }))))
	ns.db.actionBars = was
	check(Bars.Apply(), "putting the clone back reported combat deferring it")
	check(key({ kind = "item", link = link }) == "Z",
		"the key line did not survive the clone being put back")

	-- On a bar with no key on it: the item is on a bar and nothing presses it,
	-- which is the one case the bag is the honest answer to.
	local bindings = _G.WarriorKitBindings
	local kept = bindings.ACTIONBUTTON3
	bindings.ACTIONBUTTON3 = nil
	Bars.ApplyBindings()
	check(key({ kind = "item", link = link }) == "none",
		("with the key unbound the hearthstone says %s")
			:format(tostring(key({ kind = "item", link = link }))))
	bindings.ACTIONBUTTON3 = kept
	Bars.ApplyBindings()

	slots[seat] = nil
	print(("tips   the hearthstone on slot %d is pressed by %s, read with the clone %s")
		:format(seat, Bound.Text("Z"), on and "on" or "off"))
end
