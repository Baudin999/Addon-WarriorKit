local ADDON, ns = ...

local Places = {}
ns.MapPlaces = Places

--------------------------------------------------------------------------
-- The places Questie can put on a map, as a checklist
--
-- Flight masters, innkeepers, mailboxes, repairers, trainers and the vendors
-- that sell food, drink and ammunition: none of them is a quest, and all of
-- them are the reason a level twelve opens a map in a town. Questie knows where
-- every one of them stands and draws them on request, and the request is a
-- dropdown behind a minimap button, which is the one part of Questie this
-- addon's minimap corral puts away. So the request lives here as well.
--
-- **It reads Questie's menu rather than Questie's tables.** Questie's dropdown
-- is built out of three lists, one entry per kind of place: the label in the
-- player's language, whether it is on, and a function that flips it. The
-- function is the whole of what a click on Questie's menu does: it writes the
-- profile and spawns or unloads the frames Map/Pins.lua reads. Calling it is
-- exactly a click on Questie's own tick box, which is why nothing here decides
-- which innkeeper is the right faction, which trainer teaches your class, or
-- which vendor sells the food for your level. Questie decides that when the
-- entry is built, in the same code that answers its own menu, and a decision
-- copied here would be a second answer to drift away from the first.
--
-- Two things follow. The state is Questie's profile, not this addon's saved
-- variables, so a tick here is a tick in Questie's menu and the other way
-- round, and both maps draw the same places. And the list is whatever Questie
-- offers this character, which is not a fixed table: a rogue gets poisons, a
-- tailor gets moonwells, a hunter gets pet food, and a client whose Questie
-- has not built its lists yet gets nothing at all, which the panel says.
--
-- **Every read is guarded and the whole thing degrades to an empty list.** The
-- three builders are read by name off Questie's module and each is called
-- under pcall, because they walk Questie's saved tables and on a first ever
-- login those tables are not there yet. That is the same bargain Map/Pins.lua
-- makes, and the panel shows the reading from Places.Describe in its place.
--------------------------------------------------------------------------

-- The three lists Questie's dropdown is built from, in the order it shows them:
-- the townsfolk at the top, then the vendors, then the profession trainers.
-- Each is a function on QuestieMenu that returns a list of entries, and the
-- names are read out of Modules/QuestieMenu/QuestieMenu.lua in Questie v11.
local BUILDERS = {
	{ call = "buildTownsfolkMenu", group = "townsfolk" },
	{ call = "buildVendorMenu", group = "vendor" },
	{ call = "buildProfessionMenu", group = "trainer" },
}

-- Questie's menu module, or nil on a Questie without the three builders.
-- ns.Questie in Core is the probe and checks all three are functions.
local function Menu()
	return ns.Questie("QuestieMenu", BUILDERS[1].call, BUILDERS[2].call,
		BUILDERS[3].call)
end

-- One of Questie's entries, or nothing. A dropdown holds dividers and
-- headings as well as tick boxes, and Questie marks both: a divider is
-- isSeparator and a heading is notCheckable. What is left is a row with a
-- label, a state and a function, and anything short of that shape is skipped
-- rather than drawn as a box that does nothing.
local function Row(entry, group)
	if type(entry) ~= "table" or entry.isSeparator or entry.notCheckable then
		return nil
	end
	if type(entry.text) ~= "string" or entry.text == ""
		or type(entry.func) ~= "function" then
		return nil
	end
	return {
		label = entry.text,
		group = group,
		on = entry.checked and true or false,
		flip = entry.func,
	}
end

-- One list, read and appended. The call is pcalled because it walks Questie's
-- saved tables, and a builder that raised is a builder with nothing to show.
local function Take(menu, builder, out)
	local ok, entries = pcall(menu[builder.call])
	if not ok or type(entries) ~= "table" then
		return
	end
	for index = 1, #entries do
		local row = Row(entries[index], builder.group)
		if row then
			out[#out + 1] = row
		end
	end
end

-- Every place Questie offers this character, in Questie's own order, each with
-- its label, the group it came out of, whether it is on, and the flip.
--
-- Built fresh on every call rather than held, for the reason ns.Questie caches
-- nothing: Questie fills its lists after login and changes them when you
-- level, learn a profession or tame a pet, and a list held from the panel's
-- build would be the list for a character you no longer are.
function Places.List()
	local out = {}
	local menu = Menu()
	if not menu then
		return out
	end
	for index = 1, #BUILDERS do
		Take(menu, BUILDERS[index], out)
	end
	return out
end

-- The row with that label, or nil. Labels are Questie's own, in the player's
-- language, matched without regard to case because the slash word hands over
-- whatever was typed, and the first match wins where two lists carry one word.
local function Find(label)
	local want = type(label) == "string" and label:lower() or nil
	local rows = Places.List()
	for index = 1, #rows do
		if rows[index].label:lower() == want then
			return rows[index]
		end
	end
	return nil
end

-- Whether one kind of place is on, or nil for a kind Questie does not offer.
-- Spelt out rather than as an and-or, because an off row is false and false
-- through an and-or is the nil that means Questie never heard of it.
function Places.On(label)
	local row = Find(label)
	if not row then
		return nil
	end
	return row.on
end

-- One kind of place switched on or off, through Questie's own flip.
--
-- The flip is a toggle rather than a set, so it is called only when the state
-- differs from what was asked: calling it on a box already ticked would untick
-- it, and a panel tick box that unticks things is a panel nobody trusts.
-- Comes back true when Questie was asked to change something, false when it
-- already agreed, and nil for a label it does not offer.
function Places.Set(label, on)
	local row = Find(label)
	if not row then
		return nil
	end
	if row.on == (on and true or false) then
		return false
	end
	local ok, why = pcall(row.flip)
	if not ok then
		ns.Print(("Questie would not switch %s: %s"):format(label, tostring(why)))
		return false
	end
	return true
end

-- Every label, with the ones that are on marked, for the slash word. One
-- string per row so the caller decides how to print it.
function Places.Lines()
	local rows = Places.List()
	local lines = {}
	for index = 1, #rows do
		local row = rows[index]
		lines[index] = ("%s: %s"):format(row.label, row.on and "on" or "off")
	end
	return lines
end

function Places.Describe()
	if not Menu() then
		return "Questie is not answering, so there are no places to switch on"
	end
	local rows = Places.List()
	if #rows == 0 then
		return "Questie has not built its list of places yet"
	end
	local on = 0
	for index = 1, #rows do
		if rows[index].on then
			on = on + 1
		end
	end
	return ("%d kinds of place Questie can draw, %d of them on"):format(#rows, on)
end
