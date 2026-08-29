-- The client's own tooltip, as much of it as UI/Scan.lua reads
--
-- The stats on an item, the rank and the cost on an action slot, the sentence
-- under a debuff: all of it is computed inside the game and no API hands it
-- over. The addon reads it the only supported way, by pointing a hidden
-- GameTooltip at the thing and reading the font strings back, and until this
-- file existed the stub answered none of that. CreateFrame ignored the
-- template, the probe in UI/Scan.lua failed, and every tooltip in the addon
-- that draws the client's own words fell through to its title. The whole path
-- was untested and looked tested.
--
-- So a frame asked for with GameTooltipTemplate comes back doing the five
-- things the scanner leans on: it takes an owner, it clears, it takes a setter,
-- it counts its lines, and its lines are reachable as globals built from its
-- own name.
--
-- **What it says is a section's to decide.** H.tooltips is one table per kind,
-- keyed by whatever the setter is passed, and a section seeds the entry it is
-- about to hover. There is no default answer on purpose: a stub that invented a
-- line for every question would make "the client said nothing" unreachable, and
-- that is the state half the fallbacks in the addon exist for.
--
-- What this cannot prove is that the game agrees. The line count, the order and
-- the colours are modelled from the contract, and a model that is wrong is a
-- test that passes and a client that does not.

local H = ...
local child = H.child

-- Keyed by what the setter is passed. A link for an item, a slot number for an
-- action, and unit plus index or slot for the other three, joined with a colon
-- because a table keyed on two values is two tables.
--
-- One entry is an array of lines and one line is `{ left, right, color }`,
-- where color is three numbers and is left out on every line whose colour does
-- not carry information.
local tooltips = { item = {}, action = {}, buff = {}, debuff = {}, inventory = {} }
H.tooltips = tooltips

local function Pair(unit, at)
	return tostring(unit) .. ":" .. tostring(at)
end
H.tooltipKey = Pair

local function String(frame, side, index)
	local name = frame.name .. "Text" .. side .. index
	local found = _G[name]
	if not found then
		found = child("fontstring", frame, name)
	end
	return found
end

local function Fill(frame, lines)
	frame.lines = lines or {}
	for index = 1, #frame.lines do
		local line = frame.lines[index]
		local left = String(frame, "Left", index)
		left:SetText(line[1] or "")
		local color = line[3]
		left:SetTextColor(color and color[1] or 1, color and color[2] or 1,
			color and color[3] or 1)
		String(frame, "Right", index):SetText(line[2] or "")
	end
	return #frame.lines
end

local function Setter(kind, key)
	return function(self, a, b)
		local at = key and key(a, b) or a
		return Fill(self, tooltips[kind][at])
	end
end

local function Dress(frame)
	frame.lines = {}

	frame.SetOwner = function() return true end
	frame.Show = function(self) self.shown = true end
	frame.Hide = function(self) self.shown = false end

	frame.ClearLines = function(self)
		for index = 1, #self.lines do
			String(self, "Left", index):SetText("")
			String(self, "Right", index):SetText("")
		end
		self.lines = {}
	end
	frame.NumLines = function(self) return #self.lines end

	-- The client raises on a malformed link rather than answering nothing, which
	-- is why every setter in UI/Scan.lua goes through a pcall. A string with no
	-- |H...|h in it is what somebody typing an item name by hand produces, and
	-- it has to reach that pcall from here or the guard is untested.
	frame.SetHyperlink = function(self, link)
		if type(link) ~= "string" or not link:find("|H.-|h") then
			error("malformed link: " .. tostring(link), 0)
		end
		return Fill(self, tooltips.item[link])
	end

	frame.SetAction = Setter("action")
	frame.SetUnitBuff = Setter("buff", Pair)
	frame.SetUnitDebuff = Setter("debuff", Pair)
	frame.SetInventoryItem = Setter("inventory", Pair)
end

local made = _G.CreateFrame
_G.CreateFrame = function(kind, name, parent, template)
	local frame = made(kind, name, parent, template)
	if template == "GameTooltipTemplate" then
		Dress(frame)
	end
	return frame
end
