-- The professions.
--
-- Two windows, because the client has two and the addon walks both. Every
-- profession but enchanting is the trade skill window and answers the
-- GetTradeSkill names; enchanting is the craft window and answers a parallel
-- set whose returns are in a different order. That difference is the whole
-- reason this file exists rather than one window standing in for both: the
-- trade skill row says what kind of row it is second and the craft row says it
-- third, and a stub that answered the same shape twice would agree with a Core
-- shim that read the wrong slot.
--
-- What is modelled and is not a convenience: a category folded up hides its
-- recipes. The client does not answer a list with holes in it, it answers a
-- shorter list, so the rows here are derived from the fixture rather than being
-- the fixture. That is the one thing the reagent walk has to get right, because
-- a walk that could not see everything is a walk that must not delete anything.

local H = ...
local ITEMS, itemLink = H.ITEMS, H.itemLink

-- The reagents, added to the item table the rest of the client reads so a link
-- off a recipe reads back as an id exactly the way a link out of a bag does.
-- Class 7 is a trade good, which is what every one of these is.
ITEMS["Copper Bar"] = { id = 7001, classId = 7, quality = 1, price = 40,
	icon = "Interface\\Icons\\Bar", stack = 20 }
ITEMS["Rough Stone"] = { id = 7002, classId = 7, quality = 1, price = 10,
	icon = "Interface\\Icons\\Stone", stack = 20 }
ITEMS["Silver Bar"] = { id = 7003, classId = 7, quality = 1, price = 300,
	icon = "Interface\\Icons\\Bar", stack = 20 }
ITEMS["Coarse Stone"] = { id = 7004, classId = 7, quality = 1, price = 25,
	icon = "Interface\\Icons\\Stone", stack = 20 }
-- Strange Dust is not here: 04-hands.lua already carries it, with the subclass
-- the loot filter's enchanting rule reads, and a second definition under the
-- same name would land on top of that one and take the subclass away.
ITEMS["Lesser Magic Essence"] = { id = 7006, classId = 7, quality = 1, price = 400,
	icon = "Interface\\Icons\\Essence", stack = 10 }

-- One profession, in the shape the window lists it: two categories with recipes
-- under each. Two headers rather than one because a header is the row the walk
-- has to skip, and a fixture with one of them proves only that the walk skipped
-- the first row.
--
-- The tables are the file's own and a section reaches them through the handle
-- at the foot, which is how 70-reagents.lua takes a recipe away and puts it
-- back without this file carrying a call for it.
local TRADE = {
	Blacksmithing = {
		{ header = true, expanded = true, name = "Weapons" },
		{ name = "Rough Sharpening Stone", reagents = { "Rough Stone" } },
		{ name = "Copper Chain Belt", reagents = { "Copper Bar" } },
		{ header = true, expanded = true, name = "Armor" },
		{ name = "Silvered Bronze Breastplate",
			reagents = { "Silver Bar", "Coarse Stone", "Copper Bar" } },
	},
}

-- Enchanting, which is the craft window. A shorter list on purpose: what this
-- fixture is for is that a second window's ids join the first window's without
-- either replacing the other, and two recipes say that as well as twenty.
local CRAFTS = {
	Enchanting = {
		{ header = true, expanded = true, name = "Bracer" },
		{ name = "Enchant Bracer - Minor Health", reagents = { "Strange Dust" } },
		{ name = "Enchant Chest - Lesser Mana",
			reagents = { "Lesser Magic Essence", "Strange Dust" } },
	},
}

local trade, craft, linked = nil, nil, false

-- What a window is listing. A category that is folded up is on the list and
-- everything under it is not, which is the client's own answer and the shape
-- the walk has to survive.
local function listing(fixture)
	local out = {}
	local hidden = false
	for _, row in ipairs(fixture or {}) do
		if row.header then
			hidden = not row.expanded
			out[#out + 1] = row
		elseif not hidden then
			out[#out + 1] = row
		end
	end
	return out
end

local function tradeRows()
	return listing(trade and TRADE[trade])
end

local function craftRows()
	return listing(craft and CRAFTS[craft])
end

-- The reagent link for one row of one window, or nil where the index names a
-- row that is not there. The client answers nil for an index off the end and
-- for a category, and both are indexes the addon is not supposed to ask about.
local function reagentAt(rows, index, which)
	local row = rows[index]
	local name = row and row.reagents and row.reagents[which]
	if not name then
		return nil
	end
	return itemLink(name)
end

-- UNKNOWN and three zeroes with no window open, which is the client's own
-- answer and is the reason ns.TradeSkillName reads that string as "no window"
-- rather than as a profession nobody has heard of.
_G.GetTradeSkillLine = function()
	if not trade then
		return "UNKNOWN", 0, 0
	end
	return trade, 300, 375
end

_G.GetNumTradeSkills = function()
	return #tradeRows()
end

_G.GetTradeSkillInfo = function(index)
	local row = tradeRows()[index]
	if not row then
		return nil
	end
	return row.name, row.header and "header" or "optimal", 1, row.expanded and true or false
end

_G.GetTradeSkillNumReagents = function(index)
	local row = tradeRows()[index]
	return row and row.reagents and #row.reagents or 0
end

_G.GetTradeSkillReagentItemLink = function(index, which)
	return reagentAt(tradeRows(), index, which)
end

_G.IsTradeSkillLinked = function()
	return linked
end

_G.GetCraftDisplaySkillLine = function()
	if not craft then
		return "UNKNOWN", 0, 0
	end
	return craft, 300, 375
end

_G.GetNumCrafts = function()
	return #craftRows()
end

-- The kind third and the expanded flag fifth, which is where the craft window
-- really puts them and is the one thing about this file that is not the same
-- as the trade skill half above.
_G.GetCraftInfo = function(index)
	local row = craftRows()[index]
	if not row then
		return nil
	end
	return row.name, nil, row.header and "header" or "optimal", 1,
		row.expanded and true or false
end

_G.GetCraftNumReagents = function(index)
	local row = craftRows()[index]
	return row and row.reagents and #row.reagents or 0
end

_G.GetCraftReagentItemLink = function(index, which)
	return reagentAt(craftRows(), index, which)
end

-- The handle a section drives all of this from. Opening a window fires the
-- event the client fires and nothing else happens on its own, which is the
-- point: the section decides when an update comes past.
H.professions = {
	TRADE = TRADE,
	CRAFTS = CRAFTS,
	open = function(name)
		trade = name
		H.fire("TRADE_SKILL_SHOW")
	end,
	update = function()
		H.fire("TRADE_SKILL_UPDATE")
	end,
	close = function()
		trade = nil
	end,
	openCraft = function(name)
		craft = name
		H.fire("CRAFT_SHOW")
	end,
	updateCraft = function()
		H.fire("CRAFT_UPDATE")
	end,
	closeCraft = function()
		craft = nil
	end,
	-- Somebody else's profession, opened from a link in chat. A flag rather
	-- than a second fixture, because what the addon has to do about it is
	-- refuse to read the window at all.
	link = function(yes)
		linked = yes and true or false
	end,
}
